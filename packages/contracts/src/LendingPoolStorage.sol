// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

/**
 * @title LendingPoolStorage
 * @notice Stores the state and configuration for the Lending Pool.
 * @dev This contract is used internally by the Lending Pool to manage reserves, users, and other protocol data.
 */
contract LendingPoolStorage {
    /**
     * @notice Provides access to addresses within the protocol, such as oracles or lending pools.
     * @dev This is an internal reference to the addresses provider contract.
     */
    ILendingPoolAddressesProvider internal _addressesProvider;

    /**
     * @notice Mapping of reserve data by asset address.
     * @dev Stores the configuration and state of each reserve.
     */
    mapping(address => DataTypes.ReserveData) internal _reserves;

    /**
     * @notice Mapping of user configuration by user address.
     * @dev Stores the collateral and borrowing configuration for each user.
     */
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    // chainId => bytes32 (is underlying native, is there Super Asset, locator, ... )
    // locator => bool (is intracluster or intercluster)

    /**
     * @notice List of reserves indexed by reserve ID.
     * @dev Maps a reserve's unique ID to its corresponding address.
     */
    mapping(uint256 => address) internal _reservesList;

    /**
     * @notice Total count of reserves in the protocol.
     */
    uint256 internal _reservesCount;

    /**
     * @notice Indicates if the protocol is paused.
     * @dev When `true`, all protocol operations are temporarily halted.
     */
    bool internal _paused;

    // TODO: remove this
    /**
     * @notice Maximum size of stable rate borrow as a percentage of total liquidity.
     */
    uint256 internal _maxStableRateBorrowSizePercent;

    /**
     * @notice Premium fee applied to flash loans.
     * @dev Expressed as a percentage in basis points (bps).
     */
    uint256 internal _flashLoanPremiumTotal;

    /**
     * @notice Maximum number of reserves that can be supported by the protocol.
     */
    uint256 internal _maxNumberOfReserves;

    // For eliminating external calls each time we deposit ,withdraw etc..
    address rVaultAsset;
    uint256 pool_type; // 1 for op_superchain cluster and other for other clusters

    //  The Base asset of the pool is the bottom most in the hierarchy that the pool accepts to operate on.
    // For example , if you see in TokensLogic.getPoolTokenInformation() , on superchain , the baseAsset is superAsset ( and pool type is 1 )
    // and in other clusters , the base asset is the underlying token because there is no SuperAsset on other clusters ( as for now )

    address baseAsset;

    // If the chain is superchain , the superAsset has some underlying , we will store that in this variable
    address underlying_of_superAsset;
}
