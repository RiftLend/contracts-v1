// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingRateOracle} from "./interfaces/ILendingRateOracle.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";

contract LendingRateOracle is ILendingRateOracle, SuperOwnable {
    mapping(address => uint256) borrowRates;
    mapping(address => uint256) liquidityRates;

    constructor(address owner) {
        _initializeSuperOwner(uint64(block.chainid), owner);
    }

    function getMarketBorrowRate(address _asset) external view override returns (uint256) {
        return borrowRates[_asset];
    }

    function setMarketBorrowRate(address _asset, uint256 _rate) external override onlyOwner {
        borrowRates[_asset] = _rate;
    }

    function getMarketLiquidityRate(address _asset) external view returns (uint256) {
        return liquidityRates[_asset];
    }

    function setMarketLiquidityRate(address _asset, uint256 _rate) external onlyOwner {
        liquidityRates[_asset] = _rate;
    }
}
