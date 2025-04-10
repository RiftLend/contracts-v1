// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {ISuperAsset} from "src/interfaces/ISuperAsset.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import {
    Origin,
    MessagingReceipt,
    ILayerZeroEndpointV2,
    MessagingParams
} from "src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "src/libraries/helpers/layerzero/OFT.sol";
import {OFT} from "src/libraries/helpers/layerzero/OFT.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {SendParam, MessagingFee, OFTReceipt} from "src/libraries/helpers/layerzero/IOFT.sol";
import {SuperOwnable} from "src/interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {OFTLogic} from "src/libraries/logic/OFTLogic.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {OFTMsgCodec} from "src/libraries/helpers/layerzero/OFTMsgCodec.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";

contract RVaultAsset is Initializable, SuperOwnable, OFT {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ILendingPoolAddressesProvider public provider;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint8 public pool_type; // 1 - superchain, unset for ethereum and arbitrum instances
    address public underlying;
    uint128 lzComposeGasLimit;
    uint128 lzReceiveGasLimit;
    uint256 public withdrawCoolDownPeriod;
    uint256 public maxDepositLimit;

    mapping(address user => uint256 balance) public balances;
    mapping(address => uint256) public _lastWithdrawalTime;
    mapping(uint256 => uint32) public chainToEid;
    mapping(address => bool) public isSupportedBungeeTarget;

    uint256[50] __gap;

    error ONLY_ROUTER_CALL();
    error DEPOSIT_LIMIT_EXCEEDED();
    error BUNGEE_TARGET_NOT_SUPPORTED();
    error WITHDRAW_COOLDOWN_PERIOD_NOT_ELAPSED();
    error BUNGEE_BRIDGING_FAILED();
    error UNAUTHORIZED_ASSET();
    error OFT_SEND_FAILED();
    error UNAUTHORIZED_SENDER();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Events                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CrossChainBridgeUnderlyingSent(bytes txData, uint256 timestamp);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyRouter() {
        if (provider.getRouter() != msg.sender) {
            revert ONLY_ROUTER_CALL();
        }

        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Constructor                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    constructor(address ownerAddr) {
        _initializeSuperOwner(uint64(block.chainid), ownerAddr);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           Initialize Constructor Values                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(RVaultAssetInitializeParams memory params) external initializer onlyOwner {
        underlying = params.underlying;
        provider = params.provider;
        pool_type = params.provider.getPoolType();

        _name = params.name;
        _symbol = params.symbol;
        _decimals = params.decimals;
        withdrawCoolDownPeriod = params.withdrawCoolDownPeriod;
        maxDepositLimit = params.maxDepositLimit;
        lzReceiveGasLimit = params.lzReceiveGasLimit;
        lzComposeGasLimit = params.lzComposeGasLimit;
        _initializeSuperOwner(uint64(block.chainid), params.owner);
        OFT__Init(params.lzEndpoint, params.delegate, params.decimals);

        for (uint256 i = 0; i < params.lzEidChains.length; i++) {
            chainToEid[params.lzEidChains[i]] = params.lzEids[i];
            _setPeer(params.lzEids[i], bytes32(uint256(uint160(address(this)))));
        }
    }

    /// @param shares - the amount of shares to mint
    /// @param receiver - the address to which the shares are minted
    function mint(uint256 shares, address receiver) external returns (uint256) {
        return deposit(shares, receiver);
    }

    /// @param assets - the amount of assets to deposit
    /// @param receiver - the address to which the assets are deposited
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        if (totalAssets() + assets > maxDepositLimit) {
            revert DEPOSIT_LIMIT_EXCEEDED();
        }

        balances[receiver] += assets;
        super._mint(receiver, assets);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);

        return assets;
    }

    /// @notice burn shares and send underlying to user if on same chain else bridge underlying to user
    /// @param receiverOfUnderlying - user who is receiving the underlying
    /// @param toChainId - chainId to which the underlying is to be bridged
    /// @param amount - amount of shares to be burned
    function burn(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable {
        if (toChainId != block.chainid) {
            _bridge(receiverOfUnderlying, toChainId, amount);
        } else {
            _burn(msg.sender, amount);
            handleCurentChainTransfer(receiverOfUnderlying, amount);
        }
    }

    function handleCurentChainTransfer(address receiverOfUnderlying, uint256 amount) internal {
        uint256 totalUnderylying = totalAssets();
        uint256 sendAmount;
        // when rVaultAsset does not have enough uderlying due to bridging
        if (totalUnderylying >= amount) sendAmount = amount;
        else sendAmount = totalUnderylying;

        uint256 rVaultToBeMinted = amount - sendAmount;
        if (rVaultToBeMinted > 0) super._mint(receiverOfUnderlying, rVaultToBeMinted);

        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(receiverOfUnderlying, sendAmount);
        } else {
            IERC20(underlying).safeTransfer(receiverOfUnderlying, sendAmount);
        }
    }

    /// @notice withdraws underlying from the rVaultAsset
    /// @param _assets - the amount of underlying to withdraw
    /// @param _receiver - the address to which the underlying is to be sent
    /// @param _owner - the address of the owner of the rVaultAsset
    function withdraw(uint256 _assets, address _receiver, address _owner) public returns (uint256 shares) {
        if (block.timestamp - _lastWithdrawalTime[_owner] < withdrawCoolDownPeriod) {
            revert WITHDRAW_COOLDOWN_PERIOD_NOT_ELAPSED();
        }
        _lastWithdrawalTime[_owner] = block.timestamp;
        shares = _assets;
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares);
        _burn(_owner, shares);
        if (pool_type == 1) ISuperAsset(underlying).withdraw(_receiver, shares);
        else IERC20(underlying).safeTransfer(_receiver, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Bridge underlying                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function bridgeUnderlying(
        address payable _bungeeTarget,
        bytes memory txData,
        address _bungeeAllowanceTarget,
        address _underlying,
        uint256 _underlyingAmount
    ) external onlySuperAdmin {
        if (!isSupportedBungeeTarget[_bungeeTarget]) {
            revert BUNGEE_TARGET_NOT_SUPPORTED();
        }
        if (pool_type == 1) {
            ISuperAsset(_underlying).withdraw(address(this), _underlyingAmount);
        }

        IERC20(_underlying).approve(_bungeeAllowanceTarget, _underlyingAmount);
        (bool success,) = _bungeeTarget.call(txData);
        if (!success) revert BUNGEE_BRIDGING_FAILED();

        emit CrossChainBridgeUnderlyingSent(txData, block.timestamp);
    }

    /// @notice On receiving side of the bridgeUnderlying call, this function will be called to send the underlying to desired address
    /// @dev the _asset passed cannot be the underlying asset of the rVaultAsset, this function is used cause bungee bridge may sometimes return anySwap or hop tokens that would need manual swapping. https://docs.bungee.exchange/socket-api/guides/bungee-smart-contract-integration#3-destination-contract
    /// @param _asset - asset to be withdrawn
    /// @param _recipient - address to which the underlying is to be sent
    /// @param _amount - amount of underlying to be sent
    function withdrawTokens(address _asset, address _recipient, uint256 _amount) external onlyOwner {
        if (_asset != underlying) revert UNAUTHORIZED_ASSET();
        IERC20(_asset).safeTransfer(_recipient, _amount);
    }

    function _send(SendParam memory _sendParam, MessagingFee memory _fee, address _refundAddress)
        internal
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, 0);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        if (msgReceipt.guid == 0 && msgReceipt.nonce == 0) {
            revert OFT_SEND_FAILED();
        }

        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(0, 0);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, 0, 0);
    }

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) public payable override {
        (address receiverOfUnderlying, uint256 amount, address oftTxCaller) = OFTLogic.decodeMessage(_message);
        if (msg.sender != address(endpoint) && oftTxCaller != address(this)) {
            revert UNAUTHORIZED_SENDER();
        }
        if (_getPeerOrRevert(_origin.srcEid) != _origin.sender) {
            revert OnlyPeer(_origin.srcEid, _origin.sender);
        }
        handleCurentChainTransfer(receiverOfUnderlying, amount);

        emit OFTReceived(_guid, _origin.srcEid, address(0), 0);
    }

    /// @notice also write the invariant for bridging ie. sumof RVaultAsset + sumof underlying (source) = sumof RVaultAsset + sumof underlying (source)
    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable onlyRouter {
        _bridge(receiverOfUnderlying, toChainId, amount);
    }

    function _bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) internal {
        _burn(msg.sender, amount);
        if (toChainId != block.chainid) {
            (SendParam memory sendParam, MessagingFee memory fee) = getFeeQuote(receiverOfUnderlying, toChainId, amount);
            _send(sendParam, fee, payable(address(this)));
        } else {
            handleCurentChainTransfer(receiverOfUnderlying, amount);
        }
    }

    event loggerUint(uint256);
    event logger(string);
    event loggerBytes(bytes);
    event loggerBytes32(bytes32);

    function getFeeQuote(address receiverOfUnderlying, uint256 toChainId, uint256 amount)
        public
        view
        returns (SendParam memory sendParam, MessagingFee memory fee)
    {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(lzReceiveGasLimit, 0)
            .addExecutorLzComposeOption(0, lzComposeGasLimit, 0);
        bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, amount);
        sendParam = SendParam(
            chainToEid[toChainId], bytes32(uint256(uint160(address(this)))), 0, 0, options, compose_message, ""
        );

        // same as in send
        uint256 amountReceivedLD = amount;
        // @dev Builds the options and OFT message to quote in the endpoint.
        bytes memory message;
        (message, options) = _buildMsgAndOptions(sendParam, amountReceivedLD);
        fee = endpoint.quote(
            MessagingParams(sendParam.dstEid, _getPeerOrRevert(sendParam.dstEid), message, options, false),
            address(this)
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Privileged Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setWithdrawCoolDownPeriod(uint256 _withdrawCoolDownPeriod) public onlySuperAdmin {
        withdrawCoolDownPeriod = _withdrawCoolDownPeriod;
    }
    // Setter function for chain to EID mapping

    function setChainToEid(uint256 _chainId, uint32 _eid) external onlySuperAdmin {
        chainToEid[_chainId] = _eid;
    }

    function setAllLimits(uint128 _lzReceiveGasLimit, uint128 _lzComposeGasLimit, uint256 _maxDeposit)
        external
        onlySuperAdmin
    {
        lzReceiveGasLimit = _lzReceiveGasLimit;
        lzComposeGasLimit = _lzComposeGasLimit;
        maxDepositLimit = _maxDeposit;
    }

    // setter for isSupported bungee target ( also a toggler by design)
    function setIsSupportedBungeeTarget(address _target, bool isSupported) public onlySuperAdmin {
        isSupportedBungeeTarget[_target] = isSupported;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20 Functions                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        bool success = super.transfer(recipient, amount);
        if (success) {
            balances[msg.sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override(ERC20) returns (bool) {
        bool success = super.transferFrom(sender, recipient, amount);
        if (success) {
            balances[sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*      ERC4626 Vault compliant functions                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function asset() external view returns (address) {
        return underlying;
    }

    function totalAssets() internal view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    function _setOwner(address newOwner) internal override(Ownable, SuperOwnable) {
        SuperOwnable._setOwner(newOwner);
    }

    /*..•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /*                  SUPER OWNABLE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function completeOwnershipHandover(address pendingOwner) public payable override(SuperOwnable, Ownable) {
        SuperOwnable.completeOwnershipHandover(pendingOwner);
    }

    function renounceOwnership() public payable override(SuperOwnable, Ownable) {
        SuperOwnable.renounceOwnership();
    }

    function transferOwnership(address newOwner) public payable override(SuperOwnable, Ownable) {
        SuperOwnable.transferOwnership(newOwner);
    }

    /*..•°.*°.˚:*•˚°.*°.˚: •°.*:*•*/
    /*       Receive Method       */
    /*.•°:°.´+˚+°.• • °.•´+°.•´+•*/
    receive() external payable {}
}
