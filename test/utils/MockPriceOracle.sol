pragma solidity 0.8.25;

import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";
import {console} from "forge-std/console.sol";

contract MockPriceOracle is IPriceOracleGetter {
    address admin;
    uint256 price;

    constructor() {
        admin = msg.sender;
    }

    function setPrice(uint256 _price) external {
        console.log(msg.sender, admin);
        require(msg.sender == admin, "Unauthorized");
        price = _price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return price;
    }
}
