// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPool} from "./ILendingPool.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";
import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
/**
 * @title IInitializableRToken
 * @notice Interface for the initialize function on RToken
 * @author Aave
 *
 */

interface IInitializableRToken {
    /**
     * @dev Emitted when an rToken is initialized
     *
     */
    event Initialized(DataTypes.RTokenInitializedEventParams params);

    /**
     * @dev Initializes the rToken
     */
    function initialize(DataTypes.RTokenInitializeParams memory initParams) external;
}
