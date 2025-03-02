// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IReserveInterestRateStrategy} from "./interfaces/IReserveInterestRateStrategy.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingRateOracle} from "./interfaces/ILendingRateOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRToken} from "./interfaces/IRToken.sol";

import {WadRayMath} from "./libraries/math/WadRayMath.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DefaultReserveInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates depending on the reserve state
 * @dev The model of interest rate is based on 2 slopes, one before the `OPTIMAL_UTILIZATION_RATE`
 * point of utilization and another from that one to 100%
 * - An instance of this same contract, can't be used across different Aave markets, due to the caching
 *   of the LendingPoolAddressesProvider
 * @author Aave
 *
 */
contract DefaultReserveInterestRateStrategy is Initializable, IReserveInterestRateStrategy, Ownable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /**
     * @dev this constant represents the utilization rate at which the pool aims to obtain most competitive borrow rates.
     * Expressed in ray
     *
     */
    uint256 public OPTIMAL_UTILIZATION_RATE;

    /**
     * @dev This constant represents the excess utilization rate above the optimal. It's always equal to
     * 1-optimal utilization rate. Added as a constant here for gas optimizations.
     * Expressed in ray
     *
     */
    uint256 public EXCESS_UTILIZATION_RATE;

    ILendingPoolAddressesProvider public addressesProvider;

    // Base variable borrow rate when Utilization rate = 0. Expressed in ray
    uint256 internal _baseVariableBorrowRate;

    // Slope of the variable interest curve when utilization rate > 0 and <= OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 internal _variableRateSlope1;

    // Slope of the variable interest curve when utilization rate > OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 internal _variableRateSlope2;

    constructor(address ownerAddr) Ownable(ownerAddr) {
        _transferOwnership(ownerAddr);
    }

    function initialize(
        ILendingPoolAddressesProvider __provider,
        uint256 __optimalUtilizationRate,
        uint256 __baseVariableBorrowRate,
        uint256 __variableRateSlope1,
        uint256 __variableRateSlope2
    ) external initializer onlyOwner {
        OPTIMAL_UTILIZATION_RATE = __optimalUtilizationRate;
        EXCESS_UTILIZATION_RATE = WadRayMath.ray() - __optimalUtilizationRate;
        addressesProvider = __provider;
        _baseVariableBorrowRate = __baseVariableBorrowRate;
        _variableRateSlope1 = __variableRateSlope1;
        _variableRateSlope2 = __variableRateSlope2;
    }

    function variableRateSlope1() external view returns (uint256) {
        return _variableRateSlope1;
    }

    function variableRateSlope2() external view returns (uint256) {
        return _variableRateSlope2;
    }

    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @param reserve The address of the reserve
     * @param liquidityAdded The liquidity added during the operation
     * @param liquidityTaken The liquidity taken during the operation
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rate, the stable borrow rate and the variable borrow rate
     *
     */
    function calculateInterestRates(
        address reserve,
        address rToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256) {
        uint256 availableLiquidity = IRToken(rToken).totalCrosschainUnderlyingAssets();
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return calculateInterestRates(reserve, availableLiquidity, totalVariableDebt, reserveFactor);
    }

    struct CalcInterestRatesLocalVars {
        uint256 totalDebt;
        uint256 currentVariableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations.
     * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface
     * @param availableLiquidity The liquidity available in the corresponding RToken
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param reserveFactor The reserve portion of the interest that goes to the treasury of the market
     * @return The liquidity rate, the stable borrow rate and the variable borrow rate
     *
     */
    function calculateInterestRates(
        address, // reserve
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 reserveFactor
    ) public view override returns (uint256, uint256) {
        CalcInterestRatesLocalVars memory vars;

        vars.totalDebt = totalVariableDebt;
        vars.currentVariableBorrowRate = 0;
        vars.currentLiquidityRate = 0;

        vars.utilizationRate = vars.totalDebt == 0 ? 0 : vars.totalDebt.rayDiv(availableLiquidity + vars.totalDebt);

        if (vars.utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessUtilizationRateRatio =
                (vars.utilizationRate - OPTIMAL_UTILIZATION_RATE).rayDiv(EXCESS_UTILIZATION_RATE);

            vars.currentVariableBorrowRate =
                _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2.rayMul(excessUtilizationRateRatio);
        } else {
            vars.currentVariableBorrowRate = _baseVariableBorrowRate
                + vars.utilizationRate.rayMul(_variableRateSlope1).rayDiv(OPTIMAL_UTILIZATION_RATE);
        }

        vars.currentLiquidityRate = _getOverallBorrowRate(totalVariableDebt, vars.currentVariableBorrowRate).rayMul(
            vars.utilizationRate
        ).percentMul(PercentageMath.PERCENTAGE_FACTOR - reserveFactor);

        return (vars.currentLiquidityRate, vars.currentVariableBorrowRate);
    }

    /**
     * @dev Calculates the overall borrow rate as the weighted average between the total variable debt and total stable debt
     * @param totalVariableDebt The total borrowed from the reserve at a variable rate
     * @param currentVariableBorrowRate The current variable borrow rate of the reserve
     * @return The weighted averaged borrow rate
     *
     */
    function _getOverallBorrowRate(uint256 totalVariableDebt, uint256 currentVariableBorrowRate)
        internal
        pure
        returns (uint256)
    {
        uint256 totalDebt = totalVariableDebt;

        if (totalDebt == 0) return 0;

        uint256 weightedVariableRate = totalVariableDebt.wadToRay().rayMul(currentVariableBorrowRate);

        uint256 overallBorrowRate = (weightedVariableRate).rayDiv(totalDebt.wadToRay());

        return overallBorrowRate;
    }
}
