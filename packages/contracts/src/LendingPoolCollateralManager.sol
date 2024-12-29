// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IRToken} from "./interfaces/IRToken.sol";
import {IVariableDebtToken} from "./interfaces/IVariableDebtToken.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import {ILendingPoolCollateralManager} from "./interfaces/ILendingPoolCollateralManager.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";

import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {Helpers} from "./libraries/helpers/Helpers.sol";
import {WadRayMath} from "./libraries/math/WadRayMath.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {ValidationLogic} from "./libraries/logic/ValidationLogic.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "./libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";

/**
 * @title LendingPoolCollateralManager contract
 * @author Aave
 * @dev Implements actions involving management of collateral in the protocol, the main one being the liquidations
 * IMPORTANT This contract will run always via DELEGATECALL, through the LendingPool, so the chain of inheritance
 * is the same as the LendingPool, to have compatible storage layouts
 *
 */
contract LendingPoolCollateralManager is ILendingPoolCollateralManager, Initializable, LendingPoolStorage {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userStableDebt;
        uint256 userVariableDebt;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToLiquidate;
        uint256 liquidationRatio;
        uint256 maxAmountCollateralToLiquidate;
        uint256 maxCollateralToLiquidate;
        uint256 debtAmountNeeded;
        uint256 healthFactor;
        uint256 liquidatorPreviousRTokenBalance;
        IRToken collateralRToken;
        bool isCollateralEnabled;
        DataTypes.InterestRateMode borrowRateMode;
        uint256 errorCode;
        string errorMsg;
    }

    /**
     * @dev As thIS contract extends the VersionedInitializable contract to match the state
     * of the LendingPool contract, the getRevision() function is needed, but the value is not
     * important, as the initialize() function will never be called here
     */
    function getRevision() internal pure returns (uint256) {
        return 0;
    }

    /**
     * @dev Function to liquidate a position if its Health Factor drops below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param sender The address of the sender
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveRToken `true` if the liquidators wants to receive the collateral RTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     * @param sendToChainId the chain id to send the collateral to if receiveRToken is `false`
     */
    function liquidationCall(
        address sender,
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveRToken,
        uint256 sendToChainId
    ) external override returns (uint256, string memory) {
        DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

        LiquidationCallLocalVars memory vars;

        (,,,, vars.healthFactor) = GenericLogic.calculateUserAccountData(
            user,
            _reserves,
            userConfig,
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle(),
            DataTypes.Action_type.LIQUIDATION
        );

        vars.userVariableDebt = Helpers.getUserCurrentDebt(user, debtReserve);

        (vars.errorCode, vars.errorMsg) = ValidationLogic.validateLiquidationCall(
            collateralReserve, debtReserve, userConfig, vars.healthFactor, vars.userVariableDebt
        );

        if (Errors.CollateralManagerErrors(vars.errorCode) != Errors.CollateralManagerErrors.NO_ERROR) {
            return (vars.errorCode, vars.errorMsg);
        }

        vars.collateralRToken = IRToken(collateralReserve.rTokenAddress);
        // ToDO : should we pass crosschain balance here or simple one ?
        // liquidation of other chain's debt should be allowed or not ?
        // if allowed, then how to handle the cross chain balance ?
        // Resolved: let getActionBasedUserBalance decide the balance based on the action type
        vars.userCollateralBalance = GenericLogic.getActionBasedUserBalance(
            user, address(vars.collateralRToken), DataTypes.Action_type.LIQUIDATION
        );

        vars.maxLiquidatableDebt = (vars.userVariableDebt).percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

        vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt ? vars.maxLiquidatableDebt : debtToCover;

        (vars.maxCollateralToLiquidate, vars.debtAmountNeeded) = _calculateAvailableCollateralToLiquidate(
            collateralReserve,
            debtReserve,
            collateralAsset,
            debtAsset,
            vars.actualDebtToLiquidate,
            vars.userCollateralBalance
        );

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
        // collateral to cover the actual amount that is being liquidated, hence we liquidate
        // a smaller amount

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        ReserveLogic.updateState(debtReserve);

        // uint256 stableDebtBurned = 0;
        uint256 variableDebtBurned = 0;

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            (, variableDebtBurned) = IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                user, vars.actualDebtToLiquidate, debtReserve.variableBorrowIndex
            );
        } else {
            // If the user doesn't have variable debt, no need to try to burn variable debt tokens
            if (vars.userVariableDebt > 0) {
                (, variableDebtBurned) = IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                    user, vars.userVariableDebt, debtReserve.variableBorrowIndex
                );
            }
        }

        ReserveLogic.updateInterestRates(
            debtReserve, debtAsset, debtReserve.rTokenAddress, vars.actualDebtToLiquidate, 0
        );

        uint256 collateralRTokenBurned = 0;
        if (receiveRToken) {
            vars.liquidatorPreviousRTokenBalance = IERC20(vars.collateralRToken).balanceOf(sender);
            vars.collateralRToken.transferOnLiquidation(user, sender, vars.maxCollateralToLiquidate);

            if (vars.liquidatorPreviousRTokenBalance == 0) {
                DataTypes.UserConfigurationMap storage liquidatorConfig = _usersConfig[sender];
                liquidatorConfig.setUsingAsCollateral(collateralReserve.id, true);
                emit ReserveUsedAsCollateralEnabled(collateralAsset, sender);
            }
        } else {
            collateralReserve.updateState();
            collateralReserve.updateInterestRates(
                collateralAsset, address(vars.collateralRToken), 0, vars.maxCollateralToLiquidate
            );

            (, collateralRTokenBurned) = vars.collateralRToken.burn(
                user, sender, sendToChainId, vars.maxCollateralToLiquidate, collateralReserve.liquidityIndex
            );
        }

        // If the collateral being liquidated is equal to the user balance,
        // we set the currency as not being used as collateral anymore
        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(collateralAsset, user);
        }
        address superAsset = _addressesProvider.getSuperAsset();

        ISuperAsset(superAsset).transfer(debtReserve.rTokenAddress, vars.actualDebtToLiquidate);
        if (debtToCover > vars.actualDebtToLiquidate) {
            ISuperAsset(superAsset).transfer(sender, debtToCover - vars.actualDebtToLiquidate);
        }

        emit LiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            vars.actualDebtToLiquidate,
            vars.maxCollateralToLiquidate,
            sender,
            receiveRToken,
            variableDebtBurned,
            collateralRTokenBurned
        );

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 userCompoundedBorrowBalance;
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 debtAssetPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 debtAssetDecimals;
        uint256 collateralDecimals;
    }

    /**
     * @dev Calculates how much of a specific collateral can be liquidated, given
     * a certain amount of debt asset.
     * - This function needs to be called after all the checks to validate the liquidation have been performed,
     *   otherwise it might fail.
     * @param collateralReserve The data of the collateral reserve
     * @param debtReserve The data of the debt reserve
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
     * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
     *                           (user balance, close factor)
     *         debtAmountNeeded: The amount to repay with the liquidation
     *
     */
    function _calculateAvailableCollateralToLiquidate(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) internal view returns (uint256, uint256) {
        uint256 collateralAmount = 0;
        uint256 debtAmountNeeded = 0;
        IPriceOracleGetter oracle = IPriceOracleGetter(_addressesProvider.getPriceOracle());

        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
        vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

        (,, vars.liquidationBonus, vars.collateralDecimals,) = collateralReserve.configuration.getParams();
        vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

        // This is the maximum possible amount of the selected collateral that can be liquidated, given the
        // max amount of liquidatable debt
        vars.maxAmountCollateralToLiquidate = (vars.debtAssetPrice * debtToCover * 10 ** vars.collateralDecimals)
            .percentMul(vars.liquidationBonus) / (vars.collateralPrice * 10 ** vars.debtAssetDecimals);

        if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = (vars.collateralPrice * collateralAmount * 10 ** vars.debtAssetDecimals)
                / (vars.debtAssetPrice * 10 ** vars.collateralDecimals).percentDiv(vars.liquidationBonus);
        } else {
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            debtAmountNeeded = debtToCover;
        }
        return (collateralAmount, debtAmountNeeded);
    }
}
