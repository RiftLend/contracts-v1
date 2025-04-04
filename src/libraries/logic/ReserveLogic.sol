// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IRToken} from "../../interfaces/IRToken.sol";
import {IVariableDebtToken} from "../../interfaces/IVariableDebtToken.sol";
import {IReserveInterestRateStrategy} from "../../interfaces/IReserveInterestRateStrategy.sol";

import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {
    RL_VARIABLE_BORROW_INDEX_OVERFLOW,
    RL_LIQUIDITY_INDEX_OVERFLOW,
    RL_RESERVE_ALREADY_INITIALIZED,
    RL_LIQUIDITY_RATE_OVERFLOW,
    RL_VARIABLE_BORROW_RATE_OVERFLOW,
    RL_STABLE_BORROW_RATE_OVERFLOW
} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ReserveLogic library
 * @author Aave
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /**
     * @dev Emitted when the state of a reserve is updated
     * @param asset The address of the underlying asset of the reserve
     * @param liquidityRate The new liquidity rate
     * @param stableBorrowRate The new stable borrow rate
     * @param variableBorrowRate The new variable borrow rate
     * @param liquidityIndex The new liquidity index
     * @param variableBorrowIndex The new variable borrow index
     *
     */
    event ReserveDataUpdated(
        address indexed asset,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    // event ReserveDataUpdated(address,uint256,uint256,uint256,uint256,uint256);
    /**
     * @dev Returns the ongoing normalized income for the reserve
     * A value of 1e27 means there is no income. As time passes, the income is accrued
     * A value of 2*1e27 means for each unit of asset one unit of income has been accrued
     * @param reserve The reserve object
     * @return the normalized income. expressed in ray
     *
     */
    function getNormalizedIncome(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        //solium-disable-next-line
        if (timestamp == uint40(block.timestamp)) {
            //if the index was updated in the same block, no need to perform any calculation
            return reserve.liquidityIndex;
        }

        uint256 cumulated =
            MathUtils.calculateLinearInterest(reserve.currentLiquidityRate, timestamp).rayMul(reserve.liquidityIndex);

        return cumulated;
    }

    /**
     * @dev Returns the ongoing normalized variable debt for the reserve
     * A value of 1e27 means there is no debt. As time passes, the income is accrued
     * A value of 2*1e27 means that for each unit of debt, one unit worth of interest has been accumulated
     * @param reserve The reserve object
     * @return The normalized variable debt. expressed in ray
     *
     */
    function getNormalizedDebt(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        //solium-disable-next-line
        if (timestamp == uint40(block.timestamp)) {
            //if the index was updated in the same block, no need to perform any calculation
            return reserve.variableBorrowIndex;
        }

        uint256 cumulated = MathUtils.calculateCompoundedInterest(reserve.currentVariableBorrowRate, timestamp).rayMul(
            reserve.variableBorrowIndex
        );

        return cumulated;
    }

    /**
     * @dev Updates the liquidity cumulative index and the variable borrow index.
     * @param reserve the reserve object
     *
     */
    function updateState(DataTypes.ReserveData storage reserve) internal {
        uint256 scaledVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply(); // debt with interest
        uint256 previousVariableBorrowIndex = reserve.variableBorrowIndex;
        uint256 previousLiquidityIndex = reserve.liquidityIndex;
        uint40 lastUpdatedTimestamp = reserve.lastUpdateTimestamp;

        (uint256 newLiquidityIndex, uint256 newVariableBorrowIndex) = _updateIndexes(
            reserve, scaledVariableDebt, previousLiquidityIndex, previousVariableBorrowIndex, lastUpdatedTimestamp
        );

        _mintToTreasury(
            reserve,
            scaledVariableDebt,
            previousVariableBorrowIndex,
            newLiquidityIndex,
            newVariableBorrowIndex,
            lastUpdatedTimestamp
        );
    }

    /**
     * @dev Accumulates a predefined amount of asset to the reserve as a fixed, instantaneous income. Used for example to accumulate
     * the flashloan fee to the reserve, and spread it between all the depositors
     * @param reserve The reserve object
     * @param totalLiquidity The total liquidity available in the reserve
     * @param amount The amount to accomulate
     *
     */
    function cumulateToLiquidityIndex(DataTypes.ReserveData storage reserve, uint256 totalLiquidity, uint256 amount)
        internal
    {
        uint256 amountToLiquidityRatio = amount.wadToRay().rayDiv(totalLiquidity.wadToRay());

        uint256 result = amountToLiquidityRatio + WadRayMath.ray();

        result = result.rayMul(reserve.liquidityIndex);
        require(result <= type(uint128).max, RL_LIQUIDITY_INDEX_OVERFLOW);

        reserve.liquidityIndex = uint128(result);
    }

    /**
     * @dev Initializes a reserve
     * @param reserve The reserve object
     * @param rTokenAddress The address of the overlying atoken contract
     * @param superAsset The address of the SuperchainAsset contract
     * @param variableDebtTokenAddress The address of the VariableDebtToken contract
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     */
    function init(
        DataTypes.ReserveData storage reserve,
        address rTokenAddress,
        address superAsset,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress
    ) external {
        require(reserve.rTokenAddress == address(0), RL_RESERVE_ALREADY_INITIALIZED);

        reserve.liquidityIndex = uint128(WadRayMath.ray());
        reserve.variableBorrowIndex = uint128(WadRayMath.ray());
        reserve.rTokenAddress = rTokenAddress;
        reserve.variableDebtTokenAddress = variableDebtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
        reserve.superAsset = superAsset;
    }

    struct UpdateInterestRatesLocalVars {
        uint256 availableLiquidity;
        uint256 newLiquidityRate;
        uint256 newVariableRate;
        uint256 totalVariableDebt;
    }

    /**
     * @dev Updates the reserve current stable borrow rate, the current variable borrow rate and the current liquidity rate
     * @param reserve The address of the reserve to be updated
     * @param liquidityAdded The amount of liquidity added to the protocol (deposit or repay) in the previous action
     * @param liquidityTaken The amount of liquidity taken from the protocol (redeem or borrow)
     *
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        address rTokenAddress,
        uint256 liquidityAdded,
        uint256 liquidityTaken
    ) internal {
        UpdateInterestRatesLocalVars memory vars;

        //calculates the total variable debt locally using the scaled total supply instead
        //of totalSupply(), as it's noticeably cheaper. Also, the index has been
        //updated by the previous updateState() call
        // @audit check
        vars.totalVariableDebt =
            IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply().rayMul(reserve.variableBorrowIndex);

        (vars.newLiquidityRate, vars.newVariableRate) = IReserveInterestRateStrategy(
            reserve.interestRateStrategyAddress
        ).calculateInterestRates(
            reserveAddress,
            rTokenAddress,
            liquidityAdded,
            liquidityTaken,
            vars.totalVariableDebt,
            reserve.configuration.getReserveFactor()
        );
        require(vars.newLiquidityRate <= type(uint128).max, RL_LIQUIDITY_RATE_OVERFLOW);
        require(vars.newVariableRate <= type(uint128).max, RL_VARIABLE_BORROW_RATE_OVERFLOW);

        reserve.currentLiquidityRate = uint128(vars.newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(vars.newVariableRate);

        emit ReserveDataUpdated(
            reserveAddress,
            vars.newLiquidityRate,
            0,
            vars.newVariableRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }

    struct MintToTreasuryLocalVars {
        uint256 currentVariableDebt;
        uint256 previousVariableDebt;
        uint256 totalDebtAccrued;
        uint256 amountToMint;
        uint256 reserveFactor;
    }

    /**
     * @dev Mints part of the repaid interest to the reserve treasury as a function of the reserveFactor for the
     * specific asset.
     * @param reserve The reserve reserve to be updated
     * @param scaledVariableDebt The current scaled total variable debt
     * @param previousVariableBorrowIndex The variable borrow index before the last accumulation of the interest
     * @param newLiquidityIndex The new liquidity index
     * @param newVariableBorrowIndex The variable borrow index after the last accumulation of the interest
     *
     */
    function _mintToTreasury(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 previousVariableBorrowIndex,
        uint256 newLiquidityIndex,
        uint256 newVariableBorrowIndex,
        uint40 // timestamp
    ) internal {
        MintToTreasuryLocalVars memory vars;

        vars.reserveFactor = reserve.configuration.getReserveFactor();

        if (vars.reserveFactor == 0) {
            return;
        }

        //calculate the last principal variable debt
        vars.previousVariableDebt = scaledVariableDebt.rayMul(previousVariableBorrowIndex);

        //calculate the new total supply after accumulation of the index
        vars.currentVariableDebt = scaledVariableDebt.rayMul(newVariableBorrowIndex);

        //debt accrued is the sum of the current debt minus the sum of the debt at the last update
        vars.totalDebtAccrued = vars.currentVariableDebt - vars.previousVariableDebt;

        vars.amountToMint = vars.totalDebtAccrued.percentMul(vars.reserveFactor);

        if (vars.amountToMint != 0) {
            IRToken(reserve.rTokenAddress).mintToTreasury(vars.amountToMint, newLiquidityIndex);
        }
    }

    /**
     * @dev Updates the reserve indexes and the timestamp of the update
     * @param reserve The reserve reserve to be updated
     * @param scaledVariableDebt The scaled variable debt
     * @param liquidityIndex The last stored liquidity index
     * @param variableBorrowIndex The last stored variable borrow index
     *
     */
    function _updateIndexes(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 timestamp
    ) internal returns (uint256, uint256) {
        uint256 currentLiquidityRate = reserve.currentLiquidityRate;

        uint256 newLiquidityIndex = liquidityIndex;
        uint256 newVariableBorrowIndex = variableBorrowIndex;

        //only cumulating if there is any income being produced
        if (currentLiquidityRate > 0) {
            uint256 cumulatedLiquidityInterest = MathUtils.calculateLinearInterest(currentLiquidityRate, timestamp);
            newLiquidityIndex = cumulatedLiquidityInterest.rayMul(liquidityIndex);
            require(newLiquidityIndex <= type(uint128).max, RL_LIQUIDITY_INDEX_OVERFLOW);

            reserve.liquidityIndex = uint128(newLiquidityIndex);

            //we need to ensure
            //that there is actual variable debt before accumulating
            if (scaledVariableDebt != 0) {
                uint256 cumulatedVariableBorrowInterest =
                    MathUtils.calculateCompoundedInterest(reserve.currentVariableBorrowRate, timestamp);
                newVariableBorrowIndex = cumulatedVariableBorrowInterest.rayMul(variableBorrowIndex);
                require(newVariableBorrowIndex <= type(uint128).max, RL_VARIABLE_BORROW_INDEX_OVERFLOW);
                reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
            }
        }

        //solium-disable-next-line
        reserve.lastUpdateTimestamp = uint40(block.timestamp);
        return (newLiquidityIndex, newVariableBorrowIndex);
    }
}
