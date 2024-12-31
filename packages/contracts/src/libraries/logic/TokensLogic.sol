pragma solidity ^0.8.0;

import "../../interfaces/ILendingPoolAddressesProvider.sol";

library TokensLogic {
    // Get type of asset configured as underlying in pool
    function getPoolTokenInformation(ILendingPoolAddressesProvider _addressesProvider)
        public
        view
        returns (address, uint256, address)
    {
        uint256 pool_type;
        address baseAsset;

        (bytes32 lendingPool, address rVaultAsset) = _addressesProvider.getRVaultAsset();

        if (lendingPool == keccak256("OpSuperchain_LENDING_POOL")) {
            pool_type = 1;
            baseAsset = _addressesProvider.getSuperAsset();
        } else {
            pool_type = 2;
            baseAsset = _addressesProvider.getUnderlying();
        }
        return (rVaultAsset, pool_type, baseAsset);
    }
}
