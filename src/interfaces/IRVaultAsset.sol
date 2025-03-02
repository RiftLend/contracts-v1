// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

import {Origin} from "../libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {SendParam, MessagingFee} from "../libraries/helpers/layerzero/IOFT.sol";

interface IRVaultAsset {
    // Events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event Mint(address indexed caller, address indexed receiver, uint256 shares, uint256 assets);
    event Redeem(
        address indexed caller, address indexed receiver, address indexed owner, uint256 shares, uint256 assets
    );

    function underlying() external view returns (address);
    function initialize(
        address underlying_,
        ILendingPoolAddressesProvider provider_,
        address lzEndpoint_,
        address delegate_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 withdrawCoolDownPeriod_,
        uint256 maxDepositLimit_,
        uint128 lzReceiveGasLimit_,
        uint128 lzComposeGasLimit_
    ) external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function bridgeUnderlying(address payable _to, bytes memory txData, address _allowanceTarget, uint256 _amount)
        external;

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;

    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable;

    // ERC4626 Vault compliant functions
    function asset() external view returns (address);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function maxDeposit(address) external view returns (uint256);

    function maxMint(address) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

    function burn(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable;

    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external;

    function pool_type() external view returns (uint8);

    function withdrawCoolDownPeriod() external view returns (uint256);

    function provider() external view returns (address);

    function setChainToEid(uint256 _chainId, uint32 _eid) external;

    function getFeeQuote(address receiverOfUnderlying, uint256 toChainId, uint256 amount)
        external
        view
        returns (SendParam memory, MessagingFee memory);
}
