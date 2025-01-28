// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IReserveInterestRateStrategy} from "../../interfaces/IReserveInterestRateStrategy.sol";

import {Helpers} from "../helpers/Helpers.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {ReserveLogic} from "./ReserveLogic.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {LPCM_NO_ERRORS,CollateralManagerErrors} from "src/libraries/helpers/Errors.sol";

/**
 * @title ReserveLogic library
 * @author Aave
 * @notice Implements functions to validate the different actions of the protocol
 */
library ValidationLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000;
    uint256 public constant REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27; //usage ratio of 95%

    /** */

    error VL_INVALID_AMOUNT();
    error VL_NO_ACTIVE_RESERVE();
    error VL_RESERVE_FROZEN();
    error VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE();
    error VL_TRANSFER_NOT_ALLOWED();
    error VL_BORROWING_NOT_ENABLED();
    error VL_COLLATERAL_BALANCE_IS_0();
    error VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD();
    error VL_COLLATERAL_CANNOT_COVER_NEW_BORROW();
    error VL_NO_DEBT_OF_SELECTED_TYPE();
    error VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE();
    error VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY();
    error VL_INVALID_INTEREST_RATE_MODE_SELECTED();
    error VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0();
    error VL_DEPOSIT_ALREADY_IN_USE();
    error VL_INCONSISTENT_FLASHLOAN_PARAMS();
    error LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD();
    error LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER();
    error LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED();


    /**
     * @dev Validates a deposit action
     * @param reserve The reserve object on which the user is depositing
     * @param amount The amount to be deposited
     */
    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        uint256 amount
    ) external view {
        (bool isActive, bool isFrozen, ) = reserve.configuration.getFlags();

        if (amount == 0) revert VL_INVALID_AMOUNT();
        if (!isActive) revert VL_NO_ACTIVE_RESERVE();
        if (isFrozen) revert VL_RESERVE_FROZEN();
    }

    //   ValidationLogic.validateWithdraw(
    //             rVaultAsset,
    //             amountToWithdraw,
    //             userBalance,
    //             _reserves,
    //             _usersConfig[sender],
    //             _reservesList,
    //             _reservesCount,
    //             _addressesProvider.getPriceOracle()
    //         );

    /**
     * @dev Validates a withdraw action
     * @param reserveAddress The address of the reserve
     * @param amount The amount to be withdrawn
     * @param userBalance The balance of the user
     * @param reservesData The reserves state
     * @param userConfig The user configuration
     * @param reserves The addresses of the reserves
     * @param reservesCount The number of reserves
     * @param oracle The price oracle
     */
    function validateWithdraw(
        address reserveAddress,
        address user,
        uint256 userBalance,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 amount,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        if (amount == 0) revert VL_INVALID_AMOUNT();
        if (amount > userBalance) revert VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE();

        (bool isActive, , ) = reservesData[reserveAddress]
            .configuration
            .getFlags();
        if (!isActive) revert VL_NO_ACTIVE_RESERVE();
        if (
            !GenericLogic.balanceDecreaseAllowed(
                reserveAddress,
                user,
                amount,
                reservesData,
                userConfig,
                reserves,
                reservesCount,
                oracle,
                DataTypes.Action_type.WITHDRAW
            )
        ) revert VL_TRANSFER_NOT_ALLOWED();
    }

    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 availableLiquidity;
        uint256 healthFactor;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
    }

    /**
     * @dev Validates a borrow action
     * @param reserve The reserve state from which the user is borrowing
     * @param userAddress The address of the user
     * @param amount The amount to be borrowed
     * @param amountInETH The amount to be borrowed, in ETH
     * @param reservesData The state of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     * @param oracle The price oracle
     */
    function validateBorrow(
        DataTypes.ReserveData storage reserve,
        address userAddress,
        uint256 amount,
        uint256 amountInETH,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        ValidateBorrowLocalVars memory vars;

        (vars.isActive, vars.isFrozen, vars.borrowingEnabled) = reserve
            .configuration
            .getFlags();
        if (!vars.isActive) revert VL_NO_ACTIVE_RESERVE();
        if (vars.isFrozen) revert VL_RESERVE_FROZEN();
        if (amount == 0) revert VL_INVALID_AMOUNT();
        if (!vars.borrowingEnabled) revert VL_BORROWING_NOT_ENABLED();

        (
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.currentLtv,
            vars.currentLiquidationThreshold,
            vars.healthFactor
        ) = GenericLogic.calculateUserAccountData(
            userAddress,
            reservesData,
            userConfig,
            reserves,
            reservesCount,
            oracle,
            DataTypes.Action_type.BORROW
        );

        if (vars.userCollateralBalanceETH == 0)
            revert VL_COLLATERAL_BALANCE_IS_0();
        if (
            vars.healthFactor <=
            GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD
        ) revert VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD();

        //add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        vars.amountOfCollateralNeededETH = (vars.userBorrowBalanceETH +
            amountInETH).percentDiv(vars.currentLtv); //LTV is calculated in percentage
        if (vars.amountOfCollateralNeededETH > vars.userCollateralBalanceETH)
            revert VL_COLLATERAL_CANNOT_COVER_NEW_BORROW();
    }

    /**
     * @dev Validates a repay action
     * @param reserve The reserve state from which the user is repaying
     * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1)
     * @param debt The borrow balance of the user
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        uint256 debt
    ) external view {
        if (!reserve.configuration.getActive()) revert VL_NO_ACTIVE_RESERVE();
        if (amountSent == 0) revert VL_INVALID_AMOUNT();
        if (debt == 0) revert VL_NO_DEBT_OF_SELECTED_TYPE();
    }

    /**
     * @dev Validates a swap of borrow rate mode.
     * @param reserve The reserve state on which the user is swapping the rate
     * @param userConfig The user reserves configuration
     * @param variableDebt The variable debt of the user
     * @param currentRateMode The rate mode of the borrow
     */
    function validateSwapRateMode(
        DataTypes.ReserveData storage reserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 variableDebt,
        DataTypes.InterestRateMode currentRateMode
    ) external view {
        (bool isActive, bool isFrozen, ) = reserve.configuration.getFlags();

        if (!isActive) revert VL_NO_ACTIVE_RESERVE();
        if (isFrozen) revert VL_RESERVE_FROZEN();
        if (currentRateMode == DataTypes.InterestRateMode.VARIABLE) {
            if (variableDebt == 0) revert VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE();

            if (
                !(!userConfig.isUsingAsCollateral(reserve.id) ||
                    reserve.configuration.getLtv() == 0 ||
                    variableDebt >
                    IERC20(reserve.rTokenAddress).balanceOf(msg.sender))
            ) revert VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY();
        } else {
            revert VL_INVALID_INTEREST_RATE_MODE_SELECTED();
        }
    }

    /**
     * @dev Validates the action of setting an asset as collateral
     * @param reserve The state of the reserve that the user is enabling or disabling as collateral
     * @param reserveAddress The address of the reserve
     * @param reservesData The data of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     * @param oracle The price oracle
     */
    function validateSetUseReserveAsCollateral(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        bool useAsCollateral,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        uint256 underlyingBalance = IERC20(reserve.rTokenAddress).balanceOf(
            msg.sender
        );

        if (underlyingBalance == 0)
            revert VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0();

        if (
            !(useAsCollateral ||
                GenericLogic.balanceDecreaseAllowed(
                    reserveAddress,
                    msg.sender,
                    underlyingBalance,
                    reservesData,
                    userConfig,
                    reserves,
                    reservesCount,
                    oracle,
                    DataTypes.Action_type.SET_USER_RESERVE_AS_COLLATERAL
                ))
        ) revert VL_DEPOSIT_ALREADY_IN_USE();
    }

    /**
     * @dev Validates a flashloan action
     * @param assets The assets being flashborrowed
     * @param amounts The amounts for each asset being borrowed
     *
     */
    function validateFlashloan(
        uint256[] memory modes,
        address[] memory assets,
        uint256[] memory amounts
    ) internal pure {
        if(
            assets.length != amounts.length || modes.length != amounts.length            
        ) revert VL_INCONSISTENT_FLASHLOAN_PARAMS();
    }

    /**
     * @dev Validates the liquidation action
     * @param collateralReserve The reserve data of the collateral
     * @param principalReserve The reserve data of the principal
     * @param userConfig The user configuration
     * @param userHealthFactor The user's health factor
     * @param userVariableDebt Total variable debt balance of the user
     *
     */
    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage principalReserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 userHealthFactor,
        uint256 userVariableDebt
    ) internal view {
        if (
            !collateralReserve.configuration.getActive() ||
            !principalReserve.configuration.getActive()
        ) 
            revert VL_NO_ACTIVE_RESERVE();
    
        if (
            userHealthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD
        )
            revert LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD();
        

        bool isCollateralEnabled = collateralReserve
            .configuration
            .getLiquidationThreshold() >
            0 &&
            userConfig.isUsingAsCollateral(collateralReserve.id);

        //if collateral isn't enabled as collateral by user, it cannot be liquidated
        if (!isCollateralEnabled) 
            revert LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED();
        if (userVariableDebt == 0) 
            revert LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER();
    }

    /**
     * @dev Validates an rToken transfer
     * @param from The user from which the rTokens are being transferred
     * @param reservesData The state of all the reserves
     * @param userConfig The state of the user for the specific reserve
     * @param reserves The addresses of all the active reserves
     * @param oracle The price oracle
     */
    function validateTransfer(
        address from,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) internal view {
        (, , , , uint256 healthFactor) = GenericLogic.calculateUserAccountData(
            from,
            reservesData,
            userConfig,
            reserves,
            reservesCount,
            oracle,
            DataTypes.Action_type.TRANSFER
        );

        if(
            healthFactor < GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD            
        ) revert VL_TRANSFER_NOT_ALLOWED();
    }
}
