// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IScaledBalanceToken} from "./IScaledBalanceToken.sol";
import {IInitializableRToken} from "./IInitializableRToken.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";

interface IRToken is IERC20, IScaledBalanceToken, IInitializableRToken {
    /**
     * @dev Emitted after the mint action
     * @param from The address performing the mint
     * @param value The amount being
     * @param index The new liquidity index of the reserve
     *
     */
    event Mint(address indexed from, uint256 value, uint256 index);

    /**
     * @dev Mints `amount` rTokens to `user`
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(address user, uint256 amount, uint256 index) external returns (bool, uint256, uint256);

    /**
     * @dev Emitted after rTokens are burned
     * @param from The owner of the rTokens, getting them burned
     * @param target The address that will receive the underlying
     * @param value The amount being burned
     * @param index The new liquidity index of the reserve
     *
     */
    event Burn(address indexed from, address indexed target, uint256 value, uint256 index);

    /**
     * @dev Emitted during the transfer action
     * @param from The user whose tokens are being transferred
     * @param to The recipient
     * @param value The amount being transferred
     * @param index The new liquidity index of the reserve
     *
     */
    event BalanceTransfer(address from, address to, uint256 value, uint256 index);

    /**
     * @dev Emitted during the cross-chain burn action
     * @param user The owner of the rTokens, getting them burned
     * @param amountScaled The amount being burned, scaled to the pool's unit
     *
     */
    event CrossChainBurn(address user, uint256 amountScaled);

    /**
     * @dev Emitted during the cross-chain mint action
     * @param user The address receiving the minted tokens
     * @param amountScaled The amount being minted, scaled to the pool's unit
     *
     */
    event CrossChainMint(address user, uint256 amountScaled);

    /**
     * @dev Burns rTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * @param user The owner of the rTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param sendToChainId The chain id to send the funds to
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     *
     */
    function burn(address user, address receiverOfUnderlying, uint256 sendToChainId, uint256 amount, uint256 index)
        external
        payable
        returns (uint256, uint256);

    /**
     * @dev Mints rTokens to the reserve treasury
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     */
    function mintToTreasury(uint256 amount, uint256 index) external returns (uint256, uint256);

    /**
     * @dev Transfers rTokens in the event of a borrow being liquidated, in case the liquidators reclaims the aToken
     * @param from The address getting liquidated, current owner of the rTokens
     * @param to The recipient
     * @param value The amount of tokens getting transferred
     *
     */
    function transferOnLiquidation(address from, address to, uint256 value) external;

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
     * assets in borrow(), withdraw() and flashLoan()
     * @param amount The amount getting transferred
     * @param toChainId The chain id to send the funds to
     * @return The amount transferred
     *
     */
    function transferUnderlyingTo(address receiverOfUnderlying, uint256 amount, uint256 toChainId)
        external
        returns (uint256);

    /**
     * @dev Invoked to execute actions on the aToken side after a repayment.
     * @param user The user executing the repayment
     * @param amount The amount getting repaid
     *
     */
    function handleRepayment(address user, uint256 amount) external;

    /**
     * @dev Returns the address of the incentives controller contract
     *
     */
    function getIncentivesController() external view returns (IAaveIncentivesController);

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
    function updateCrossChainBalance(address user, uint256 amountScaled, uint256 mode) external;

    /**
     * @dev gets the cross chain balance of user
     * @param user The user address
     * @return The user balance
     */
    function getCrossChainUserBalance(address user) external view returns (uint256);
}
