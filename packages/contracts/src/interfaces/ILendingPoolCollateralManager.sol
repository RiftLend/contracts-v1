// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/**
 * @title ILendingPoolCollateralManager
 * @author Aave
 * @notice Defines the actions involving management of collateral in the protocol.
 *
 */
interface ILendingPoolCollateralManager {
    /**
     * @dev Emitted when a borrower is liquidated. This event is emitted by the LendingPool via
     * LendingPoolCollateral manager using a DELEGATECALL
     * This allows to have the events in the generated ABI for LendingPool.
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param liquidatedCollateralAmount The amount of collateral received by the liiquidator
     * @param liquidator The address of the liquidator
     * @param receiveRToken `true` if the liquidators wants to receive the collateral rTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     * @param variableDebtBurned The amount of variable debt burned
     * @param collateralRTokenBurned The amount of collateral rTokens burned
     *
     */
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveRToken,
        uint256 variableDebtBurned,
        uint256 collateralRTokenBurned
    );

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
     * @param sender The address of the sender
     * @param collateral The address of the collateral to liquidated
     * @param principal The address of the principal reserve
     * @param user The address of the borrower
     * @param debtToCover The amount of principal that the liquidator wants to repay
     * @param receiveRToken true if the liquidators wants to receive the rTokens, false if
     * he wants to receive the underlying asset directly
     * @param sendToChainId the chain id to send the collateral to if receiveRToken is `false`
     *
     */
    function liquidationCall(
        address sender,
        address collateral,
        address principal,
        address user,
        uint256 debtToCover,
        bool receiveRToken,
        uint256 sendToChainId
    ) external returns (uint256, string memory);
}
