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
     * @dev Emitted when an aToken is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param treasury The address of the treasury
     * @param incentivesController The address of the incentives controller for this aToken
     * @param aTokenDecimals the decimals of the underlying
     * @param rTokenName the name of the aToken
     * @param rTokenSymbol the symbol of the aToken
     * @param params A set of encoded parameters for additional initialization
     *
     */
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address treasury,
        address incentivesController,
        uint8 aTokenDecimals,
        string rTokenName,
        string rTokenSymbol,
        bytes params
    );

    /**
     * @dev Initializes the aToken
     * @param pool The address of the lending pool where this aToken will be used
     * @param treasury The address of the Aave treasury, receiving the fees on this aToken
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param addressesProvider The addresses provider
     * @param aTokenDecimals The decimals of the aToken, same as the underlying asset's
     * @param rTokenName The name of the aToken
     * @param rTokenSymbol The symbol of the aToken
     * @param params A set of encoded parameters for additional initialization
     * @param crossL2Prover The address of the cross-chain prover
     */
    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IAaveIncentivesController incentivesController,
        ILendingPoolAddressesProvider addressesProvider,
        uint8 aTokenDecimals,
        string calldata rTokenName,
        string calldata rTokenSymbol,
        bytes calldata params,
        address crossL2Prover
    ) external;
}
