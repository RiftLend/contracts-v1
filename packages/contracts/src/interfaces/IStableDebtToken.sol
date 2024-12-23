// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IInitializableDebtToken} from "./IInitializableDebtToken.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";

/**
 * @title IStableDebtToken
 * @notice Defines the interface for the stable debt token
 * @dev It does not inherit from IERC20 to save in code size
 * @author Aave
 *
 */
interface IStableDebtToken is IInitializableDebtToken {
    /**
     * @dev Emitted when new stable debt is minted
     * @param user The address of the user who triggered the minting
     * @param onBehalfOf The recipient of stable debt tokens
     * @param amount The amount minted
     * @param currentBalance The current balance of the user
     * @param balanceIncrease The increase in balance since the last action of the user
     * @param newRate The rate of the debt after the minting
     * @param avgStableRate The new average stable rate after the minting
     * @param newTotalSupply The new total supply of the stable debt token after the action
     *
     */
    event Mint(
        address indexed user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 currentBalance,
        uint256 balanceIncrease,
        uint256 newRate,
        uint256 avgStableRate,
        uint256 newTotalSupply
    );

    /**
     * @dev Emitted when new stable debt is burned
     * @param user The address of the user
     * @param amount The amount being burned
     * @param currentBalance The current balance of the user
     * @param balanceIncrease The the increase in balance since the last action of the user
     * @param avgStableRate The new average stable rate after the burning
     * @param newTotalSupply The new total supply of the stable debt token after the action
     *
     */
    event Burn(
        address indexed user,
        uint256 amount,
        uint256 currentBalance,
        uint256 balanceIncrease,
        uint256 avgStableRate,
        uint256 newTotalSupply
    );

    /**
     * @dev Mints debt token to the `onBehalfOf` address
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     * of credit delegate, or same as `onBehalfOf` otherwise
     * @param onBehalfOf The address receiving the debt tokens
     * @param amount The amount of debt being minted
     * @param rate The rate of the debt being minted
     *
     */
    function mint(address user, address onBehalfOf, uint256 amount, uint256 rate)
        external
        returns (bool, uint256, uint256);

    /**
     * @dev Burns debt of `user`
     * @param user The address of the user getting his debt burned
     * @param amount The amount of debt being burned
     *
     */
    function burn(address user, uint256 amount) external returns (uint256, uint256);

    /**
     * @dev Returns the average rate of all the stable rate loans.
     * @return The average stable rate
     *
     */
    function getAverageStableRate() external view returns (uint256);

    /**
     * @dev Returns the stable rate of the user debt
     * @return The stable rate of the user
     *
     */
    function getUserStableRate(address user) external view returns (uint256);

    /**
     * @dev Returns the timestamp of the last update of the user
     * @return The timestamp
     *
     */
    function getUserLastUpdated(address user) external view returns (uint40);

    /**
     * @dev Returns the principal, the total supply and the average stable rate
     *
     */
    function getSupplyData() external view returns (uint256, uint256, uint256, uint40);

    /**
     * @dev Returns the timestamp of the last update of the total supply
     * @return The timestamp
     *
     */
    function getTotalSupplyLastUpdated() external view returns (uint40);

    /**
     * @dev Returns the total supply and the average stable rate
     *
     */
    function getTotalSupplyAndAvgRate() external view returns (uint256, uint256);

    /**
     * @dev Returns the principal debt balance of the user
     * @return The debt balance of the user since the last burn/mint action
     *
     */
    function principalBalanceOf(address user) external view returns (uint256);

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     *
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @dev Updates the cross chain balance
     * @param amountScaled The amount scaled
     * @param mode 1 if minting, 2 if burning
     */
    function updateCrossChainBalance(uint256 amountScaled, uint256 mode) external;

    /**
     * @dev Returns the address of the incentives controller contract
     */
    function getIncentivesController() external view returns (IAaveIncentivesController);
}
