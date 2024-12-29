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

    mapping(uint256 => DataTypes.Chain_Cluster_Types )public chainId_cluster_type; // is chainId intra cluter or inter-cluster

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
}
