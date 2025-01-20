pragma solidity 0.8.25;

import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";

contract MockPriceOracle is IPriceOracleGetter {
    address admin;
    mapping(address => uint256) public prices;

    constructor() {
        admin = msg.sender;
    }

    function setPrice(address asset, uint256 _price) external {
        require(msg.sender == admin, "Unauthorized");
        prices[asset] = _price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}
