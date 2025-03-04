// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {DataTypes} from "../libraries/types/DataTypes.sol";

/**
 * @title ILendingPoolCollateralManager
 * @author Aave
 * @notice Defines the actions involving management of collateral in the protocol.
 *
 */
interface ILendingPoolCollateralManager {
    event LiquidationCall(DataTypes.LiquidationCallEventParams liquidationCallEventParams);

    /**
     * @dev Emitted when a reserve is disabled as collateral for an user
     * @param reserve The address of the reserve
     * @param user The address of the user
     *
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a reserve is enabled as collateral for an user
     * @param reserve The address of the reserve
     * @param user The address of the user
     *
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Users can invoke this function to liquidate an undercollateralized position.
     *
     */
    function liquidationCall(DataTypes.CrosschainLiquidationCallData memory liquidationParams)
        external
        returns (uint256, string memory);
}
