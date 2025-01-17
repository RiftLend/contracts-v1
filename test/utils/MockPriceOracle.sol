import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";

contract MockPriceOracle is IPriceOracleGetter {
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return 10 ** decimals;
    }
}
