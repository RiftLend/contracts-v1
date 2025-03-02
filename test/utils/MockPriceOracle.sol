pragma solidity 0.8.25;

import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

contract MockPriceOracle is Ownable, IPriceOracleGetter {
    mapping(address => uint256) public prices;

    constructor(address owner) {
        _setOwner(owner);
    }

    function setPrice(address asset, uint256 _price) external onlyOwner {
        prices[asset] = _price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}
