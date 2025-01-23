// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPool} from "./ILendingPool.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";
import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";

/**
 * @title IInitializableRToken
 * @notice Interface for the initialize function on RToken
 * @author Aave
 *
 */
interface IInitializableRToken {
    /**
     * @dev Emitted when an rToken is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param treasury The address of the treasury
     * @param incentivesController The address of the incentives controller for this rToken
     * @param rTokenDecimals the decimals of the underlying
     * @param rTokenName the name of the rToken
     * @param rTokenSymbol the symbol of the rToken
     * @param params A set of encoded parameters for additional initialization
     *
     */
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address treasury,
        address incentivesController,
        uint8 rTokenDecimals,
        string rTokenName,
        string rTokenSymbol,
        bytes params
    );

    /**
     * @dev Initializes the rToken
     * @param pool The address of the lending pool where this rToken will be used
     * @param treasury The address of the Aave treasury, receiving the fees on this rToken
     * @param underlyingAsset The address of the underlying asset of this rToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param addressesProvider The addresses provider
     * @param rTokenDecimals The decimals of the rToken, same as the underlying asset's
     * @param rTokenName The name of the rToken
     * @param rTokenSymbol The symbol of the rToken
     * @param params A set of encoded parameters for additional initialization
     * @param eventValidator The address of the event validator
     */
    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IAaveIncentivesController incentivesController,
        ILendingPoolAddressesProvider addressesProvider,
        uint8 rTokenDecimals,
        string calldata rTokenName,
        string calldata rTokenSymbol,
        bytes calldata params,
        address eventValidator
    ) external;
}
