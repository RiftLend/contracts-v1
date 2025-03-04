// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

import {Origin} from "../libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {SendParam, MessagingFee} from "../libraries/helpers/layerzero/IOFT.sol";

struct RVaultAssetInitializeParams {
    address underlying;
    ILendingPoolAddressesProvider provider;
    address lzEndpoint;
    address delegate;
    string name;
    string symbol;
    uint8 decimals;
    uint256 withdrawCoolDownPeriod;
    uint256 maxDepositLimit;
    uint128 lzReceiveGasLimit;
    uint128 lzComposeGasLimit;
    address owner;
}

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
    function initialize(RVaultAssetInitializeParams memory params) external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

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

    function burn(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable;

    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external;

    function pool_type() external view returns (uint8);

    function withdrawCoolDownPeriod() external view returns (uint256);

    function provider() external view returns (address);

    function setChainToEid(uint256 _chainId, uint32 _eid) external;
    function setAllLimits(uint128 _lzReceiveGasLimit, uint128 _lzComposeGasLimit, uint256 _maxDeposit) external;

    function getFeeQuote(address receiverOfUnderlying, uint256 toChainId, uint256 amount)
        external
        view
        returns (SendParam memory, MessagingFee memory);
}
