// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IDelegationToken} from "../interfaces/IDelegationToken.sol";

import {RToken} from "./RToken.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";

/**
 * @title Aave RToken enabled to delegate voting power of the underlying asset to a different address
 * @dev The underlying asset needs to be compatible with the COMP delegation interface
 * @author Aave
 */
contract DelegationAwareRToken is RToken {
    error CALLER_NOT_POOL_ADMIN();

    modifier onlyPoolAdmin() {
        if (_msgSender() != _pool.getAddressesProvider().getPoolAdmin()) revert CALLER_NOT_POOL_ADMIN();
        _;
    }

    /**
     * @dev Delegates voting power of the underlying asset to a `delegatee` address
     * @param delegatee The address that will receive the delegation
     *
     */
    function delegateUnderlyingTo(address delegatee) external onlyPoolAdmin {
        IDelegationToken(_underlyingAsset).delegate(delegatee);
    }
}
