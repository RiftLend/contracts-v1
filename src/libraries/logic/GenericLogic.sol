// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IRToken} from "../../interfaces/IRToken.sol";
import {IVariableDebtToken} from "../../interfaces/IVariableDebtToken.sol";

import {ReserveLogic} from "./ReserveLogic.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title GenericLogic library
 * @author Aave
 * @title Implements protocol-level logic to calculate and validate the state of a user
 */
library GenericLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    struct balanceDecreaseAllowedLocalVars {
        uint256 decimals;
        uint256 liquidationThreshold;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 avgLiquidationThreshold;
        uint256 amountToDecreaseInETH;
        uint256 collateralBalanceAfterDecrease;
        uint256 liquidationThresholdAfterDecrease;
        uint256 healthFactorAfterDecrease;
        bool reserveUsageAsCollateralEnabled;
    }

    /**
     * @dev Checks if a specific balance decrease is allowed
     * (i.e. doesn't bring the user borrow position health factor under HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     * @param asset The address of the underlying asset of the reserve
     * @param user The address of the user
     * @param amount The amount to decrease
     * @param reservesData The data of all the reserves
     * @param userConfig The user configuration
     * @param reserves The list of all the active reserves
     * @param oracle The address of the oracle contract
     * @return true if the decrease of the balance is allowed
     *
     */
    function balanceDecreaseAllowed(
        address asset,
        address user,
        uint256 amount,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap calldata userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle,
        DataTypes.Action_type action_type
    ) external view returns (bool) {
        if (!userConfig.isBorrowingAny() || !userConfig.isUsingAsCollateral(reservesData[asset].id)) {
            return true;
        }

        balanceDecreaseAllowedLocalVars memory vars;

        (, vars.liquidationThreshold,, vars.decimals,) = reservesData[asset].configuration.getParams();

        if (vars.liquidationThreshold == 0) {
            return true;
        }

        (vars.totalCollateralInETH, vars.totalDebtInETH,, vars.avgLiquidationThreshold,) =
            calculateUserAccountData(user, reservesData, userConfig, reserves, reservesCount, oracle, action_type);

        if (vars.totalDebtInETH == 0) {
            return true;
        }

        vars.amountToDecreaseInETH = IPriceOracleGetter(oracle).getAssetPrice(asset) * amount / (10 ** vars.decimals);

        vars.collateralBalanceAfterDecrease = vars.totalCollateralInETH - vars.amountToDecreaseInETH;

        //if there is a borrow, there can't be 0 collateral
        if (vars.collateralBalanceAfterDecrease == 0) {
            return false;
        }

        vars.liquidationThresholdAfterDecrease = (
            vars.totalCollateralInETH * vars.avgLiquidationThreshold
                - vars.amountToDecreaseInETH * vars.liquidationThreshold
        ) / vars.collateralBalanceAfterDecrease;

        uint256 healthFactorAfterDecrease = calculateHealthFactorFromBalances(
            vars.collateralBalanceAfterDecrease, vars.totalDebtInETH, vars.liquidationThresholdAfterDecrease
        );

        return healthFactorAfterDecrease >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    struct CalculateUserAccountDataVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        uint256 reservesLength;
        bool healthFactorBelowThreshold;
        address currentReserveAddress;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
    }

    /**
     * @dev Calculates the user data across the reserves.
     * this includes the total liquidity/collateral/borrow balances in ETH,
     * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
     * @param user The address of the user
     * @param reservesData Data of all the reserves
     * @param userConfig The configuration of the user
     * @param reserves The list of the available reserves
     * @param oracle The price oracle address
     * @return The total collateral and total debt of the user in ETH, the avg ltv, liquidation threshold and the HF
     *
     */
    function calculateUserAccountData(
        address user,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap memory userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle,
        DataTypes.Action_type action_type
    ) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, type(uint256).max);
        }
        DataTypes.ReserveData storage currentReserve;
        uint256 user_balance;

        for (vars.i = 0; vars.i < reservesCount; vars.i++) {
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }

            vars.currentReserveAddress = reserves[vars.i];
            currentReserve = reservesData[vars.currentReserveAddress];

            (vars.ltv, vars.liquidationThreshold,, vars.decimals,) = currentReserve.configuration.getParams();

            vars.tokenUnit = 10 ** vars.decimals;
            vars.reserveUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(vars.currentReserveAddress);
            if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
                user_balance = getActionBasedUserBalance(user, currentReserve.rTokenAddress, action_type);

                vars.compoundedLiquidityBalance = user_balance;

                uint256 liquidityBalanceETH = (vars.reserveUnitPrice * vars.compoundedLiquidityBalance) / vars.tokenUnit;

                vars.totalCollateralInETH = vars.totalCollateralInETH + liquidityBalanceETH;

                vars.avgLtv = vars.avgLtv + (liquidityBalanceETH * vars.ltv);
                vars.avgLiquidationThreshold =
                    vars.avgLiquidationThreshold + (liquidityBalanceETH * vars.liquidationThreshold);
            }

            if (userConfig.isBorrowing(vars.i)) {
                user_balance = IERC20(currentReserve.variableDebtTokenAddress).balanceOf(user);

                vars.compoundedBorrowBalance = vars.compoundedBorrowBalance + user_balance;

                vars.totalDebtInETH =
                    vars.totalDebtInETH + ((vars.reserveUnitPrice * vars.compoundedBorrowBalance) / vars.tokenUnit);
            }
        }

        vars.avgLtv = vars.totalCollateralInETH > 0 ? vars.avgLtv / vars.totalCollateralInETH : 0;
        vars.avgLiquidationThreshold =
            vars.totalCollateralInETH > 0 ? vars.avgLiquidationThreshold / vars.totalCollateralInETH : 0;

        vars.healthFactor = calculateHealthFactorFromBalances(
            vars.totalCollateralInETH, vars.totalDebtInETH, vars.avgLiquidationThreshold
        );
        return (
            vars.totalCollateralInETH, vars.totalDebtInETH, vars.avgLtv, vars.avgLiquidationThreshold, vars.healthFactor
        );
    }

    /**
     * @dev Calculates the health factor from the corresponding balances
     * @param totalCollateralInETH The total collateral in ETH
     * @param totalDebtInETH The total debt in ETH
     * @param liquidationThreshold The avg liquidation threshold
     * @return The health factor calculated from the balances provided
     *
     */
    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (totalDebtInETH == 0) return type(uint256).max;

        return (totalCollateralInETH.percentMul(liquidationThreshold)) / 1e18;
    }

    /**
     * @dev Calculates the equivalent amount in ETH that an user can borrow, depending on the available collateral and the
     * average Loan To Value
     * @param totalCollateralInETH The total collateral in ETH
     * @param totalDebtInETH The total borrow balance
     * @param ltv The average loan to value
     * @return the amount available to borrow in ETH for the user
     *
     */
    function calculateAvailableBorrowsETH(uint256 totalCollateralInETH, uint256 totalDebtInETH, uint256 ltv)
        internal
        pure
        returns (uint256)
    {
        uint256 availableBorrowsETH = totalCollateralInETH.percentMul(ltv);

        if (availableBorrowsETH < totalDebtInETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH - totalDebtInETH;
        return availableBorrowsETH;
    }

    function getActionBasedUserBalance(address user, address tokenAddress, DataTypes.Action_type action_type)
        public
        view
        returns (uint256)
    {
        if (action_type == DataTypes.Action_type.LIQUIDATION) {
            return IRToken(tokenAddress).getCrossChainUserBalance(user);
        } else {
            return IRToken(tokenAddress).balanceOf(user);
        }
    }
}
