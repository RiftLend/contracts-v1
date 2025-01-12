// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";
import "./interfaces/IRVaultAsset.sol";
import {ISuperchainTokenBridge} from "./interfaces/ISuperchainTokenBridge.sol";
import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {ILayerZeroEndpointV2} from "./libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";

import {Ownable} from "@solady/auth/Ownable.sol";
import {Predeploys} from "./libraries/Predeploys.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "./libraries/helpers/layerzero/OFT.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {SendParam, OFTReceipt} from "./libraries/helpers/layerzero/IOFT.sol";
import {MessagingFee} from "./libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {OFTLogic} from "./libraries/logic/OFTLogic.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import "forge-std/console.sol";
import {MessagingFee, MessagingParams} from "./libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {PacketV1Codec} from "./libraries/helpers/layerzero/PacketV1Codec.sol";
import {Packet} from "./libraries/helpers/layerzero/ISendLib.sol";
import {GUID} from "./libraries/helpers/layerzero/GUID.sol";

contract RVaultAsset is SuperOwnable, OFT {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ILendingPoolAddressesProvider provider;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;

    address public immutable underlying;

    mapping(address user => uint256 balance) public balances;

    uint256 public totalBalances;
    // mapping(address => uint256) public _lastWithdrawalTime;

    uint256 public WITHDRAW_COOL_DOWN_PERIOD = 1 days;
    mapping(uint256 => DataTypes.Chain_Cluster_Types) public chainIdToClusterType;

    /// @dev true - superchain , false - OFT

    bool public isSuperTokenBridgeEnabled;
    /// @dev Only used when pool_type is 1 (OP Superchain). For other clusters, this remains unset.
    uint256 public immutable pool_type;

    address public immutable underlying_of_superAsset; // todo: think can remove this.

    // For keep record of and distrbuting to all rValtAssetHolders
    // Protection against DOS when there are huge number of rVaultAssetHolders , good to use mappings than arrays
    //todo:discuss with supercontracts.eth on edge cases
    // mapping(uint256 => address) internal rVaultAssetHolder;
    // mapping(address => bool) internal isRVaultAssetHolder;
    // TODO: umar also why do we even need this.
    // uint256 totalRVaultAssetHolders; // we cant do it like this wouldn't work highly gas consuming // we have to have amountScaled and index similar to rToken.
    // uint256 multiplier;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Events                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CrossChainBridgeUnderlyingSent(bytes txData, uint256 timestamp);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Errors                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NonConfiguredCluster(uint256 ChainId);
    error OnlyRelayerCall();
    error BridgeCrossClusterFailed();
    error OftSendFailed();
    error onlySuperAssetAdapterOrLzEndpointCall();
    error onlyRouterCall();
    error withdrawCoolDownPeriodNotElapsed();
    error UnAuthorized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyRelayer() {
        if (provider.getRelayer() != msg.sender) revert OnlyRelayerCall();
        _;
    }

    modifier onlyRouter() {
        if (provider.getRouter() != msg.sender) revert onlyRouterCall();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Constructor                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(
        address underlying_,
        ILendingPoolAddressesProvider provider_,
        address lzEndpoint_,
        address delegate_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) OFT(lzEndpoint_, delegate_, decimals_) {
        underlying = underlying_;
        provider = provider_;
        pool_type = provider.getPoolType();
        // todo:discuss rVault specific underlying asset
        if (pool_type == 1) {
            underlying_of_superAsset = ISuperAsset(underlying).underlying();
        }

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;

        _initializeSuperOwner(uint64(block.chainid), msg.sender);
    }

    /// @notice Mint's shares (1:1 peg)
    function mint(uint256 shares, address receiver) external returns (uint256) {
        return deposit(shares, receiver);
    }

    /// @notice Deposit underlying and mint shares (1:1 peg)
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        totalBalances += assets;

        balances[receiver] += assets;
        super._mint(receiver, assets);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);

        return assets;

        // if (!isRVaultAssetHolder[receiver]) {
        //     isRVaultAssetHolder[receiver] = true;
        //     rVaultAssetHolder[totalRVaultAssetHolders++] = receiver;
        // }
        // return assets;
    }

    /// @notice Burn shares and return underlying
    function burn(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external {
        // if (msg.sender != user) _spendAllowance(user, msg.sender, amount);
        // _burn(msg.sender, amount);
        // // IERC20(underlying).safeTransfer(msg.sender, address(this), amount);
        // _bridge(receiverOfUnderlying, toChainId, amount);
        // console.log("bridge success");
        // if (balances[msg.sender] == 0) isRVaultAssetHolder[msg.sender] = false;

        if (toChainId != block.chainid) {
            _bridge(receiverOfUnderlying, toChainId, amount);
        } else {
            _burn(msg.sender, amount);
            IERC20(underlying).safeTransfer(msg.sender, amount);
        }
    }

    // Withdraw assets and burn shares (1:1 peg)

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        // // Check the cooldown period
        // if (block.timestamp < _lastWithdrawalTime[owner] + WITHDRAW_COOL_DOWN_PERIOD) {
        //     revert withdrawCoolDownPeriodNotElapsed();
        // }

        // shares = assets; // 1:1 peg
        // if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        // _burn(owner, shares);
        // // Update the last withdrawal time
        // _lastWithdrawalTime[owner] = block.timestamp;
        // // unwrap underlying from superAsset
        // if (pool_type == 1) ISuperAsset(underlying).withdraw(receiver, shares);
        // else IERC20(underlying).safeTransfer(receiver, shares);
        // return shares;

        shares = assets; // 1:1 peg
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        if (pool_type == 1) ISuperAsset(underlying).withdraw(receiver, shares);
        else IERC20(underlying).safeTransfer(receiver, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Bridge underlying                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // todo: ask bungee about if there contracts can change for bridging and also do they have the same addresses
    function bridgeUnderlying(
        // we will hardcode bungee target address in the contracts to gain trust that we dont move the funds elsewhere ...
        address payable _bungeeTarget,
        bytes memory txData,
        address _bungeeAllowanceTarget,
        uint256 _underlyingAmount
    ) external onlySuperAdmin {
        address target_asset = underlying;
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(address(this), _underlyingAmount);
            target_asset = underlying_of_superAsset; // todo: @tabish i think txData contains the asset
        }
        IERC20(target_asset).approve(_bungeeAllowanceTarget, _underlyingAmount);
        (bool success,) = _bungeeTarget.call(txData);
        require(success, "Bungee Bridging failed");
        emit CrossChainBridgeUnderlyingSent(txData, block.timestamp);
    }

    //  @dev On receiving side of the bridgeUnderlying call, this function will be called to send the underlying to desired address
    function withdrawTokens(address _recipient, uint256 _amount) external onlySuperAdmin {
        IERC20(underlying).safeTransfer(_recipient, _amount);
    }

    function _bridgeCrossCluster(uint256 amount, address receiverOfUnderlying, uint256 toChainId) internal {
        // address superAssetAdapter = provider.getSuperAssetAdapter();

        // if (pool_type == 1) { // lets change pool_type to a enum. // 1 is superchain, 2 is other
        //     ISuperAsset(underlying).withdraw(address(this), tokensToSend);
        //     IERC20(ISuperAsset(underlying).underlying()).approve(superAssetAdapter, tokensToSend);

        //     bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, tokensToSend);

        //     SendParam memory sendParam = SendParam(
        //         uint32(toChainId),
        //         bytes32(uint256(uint160(address(this)))),
        //         tokensToSend,
        //         tokensToSend, // No Slippage allod
        //         "",
        //         compose_message, //  composeMsg
        //         ""
        //     );
        //     MessagingFee memory fee = ISuperAssetAdapter(superAssetAdapter).quoteSend(sendParam, false);
        //     console.log("bridgeCrosscluster sending");

        //     // (MessagingReceipt memory msgReceipt,) =
        //     ISuperAssetAdapter(superAssetAdapter).send(sendParam, fee, payable(address(this)));
        //     console.log("bridgeCrosscluster sent");

        //     // if (msgReceipt.guid == bytes32(uint256(0)) && msgReceipt.nonce == 0) {
        //     //     revert OftSendFailed();
        //     // }
        // } else {
        //     // Now there can be two cases , arb-eth cluster to superchain
        //     // or abrb-eth cluster to arb-eth

        //     bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, tokensToSend);

        //     SendParam memory sendParam = SendParam(
        //         uint32(toChainId),
        //         bytes32(uint256(uint160(address(this))));,
        //         tokensToSend,
        //         tokensToSend, // No Slippage
        //         "", // No options
        //         compose_message,
        //         "" // empty oftCmd
        //     );
        //     if (chainIdToClusterType[toChainId] == DataTypes.Chain_Cluster_Types.SUPER_CHAIN) {
        //         sendParam.to = bytes32(uint256(uint160(superAssetAdapter)));
        //         ISuperAsset(underlying).withdraw(address(this), tokensToSend);
        //         IERC20(ISuperAsset(underlying).underlying()).approve(superAssetAdapter, tokensToSend);
        //     }

        //     MessagingFee memory fee = quoteSend(sendParam, false);
        //     _send(sendParam, fee, payable(address(this)));
        // }

        bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, amount);
        SendParam memory sendParam = SendParam(
            uint32(toChainId),
            bytes32(uint256(uint160(address(this)))),
            amount,
            amount, // No Slippage
            "", // No options
            compose_message,
            "" // empty oftCmd
        );
        // MessagingFee memory fee = quoteSend(sendParam, false);
        // todo: uncomment for mainnet launch
        // _send(sendParam, fee, payable(address(this)));

        // @dev:test below lines are for testing ,
        // TODO: remove later when launch on mainnet
        MessagingParams memory messagingParams =
            MessagingParams(sendParam.dstEid, sendParam.to, compose_message, "", false);
        _sendPacket(messagingParams, uint32(toChainId), msg.sender);
        emit OFTSent(bytes32(uint256(1)), sendParam.dstEid, msg.sender, sendParam.amountLD, sendParam.minAmountLD);
    }

    function _send(SendParam memory _sendParam, MessagingFee memory _fee, address _refundAddress)
        internal
        virtual
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // @dev Applies the token transfers regarding this send() operation.
        // - amountSentLD is the amount in local decimals that was ACTUALLY sent/debited from the sender.
        // - amountReceivedLD is the amount in local decimals that will be received/credited to the recipient on the remote OFT instance.
        (uint256 amountSentLD, uint256 amountReceivedLD) =
            _debit(msg.sender, _sendParam.amountLD, _sendParam.minAmountLD, _sendParam.dstEid);

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        if (msgReceipt.guid == 0 && msgReceipt.nonce == 0) revert OftSendFailed();

        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    function _sendPacket(MessagingParams memory _params, uint32 eid, address _sender) internal {
        // construct the packet with a GUID
        uint64 latestNonce = 1;
        Packet memory packet = Packet({
            nonce: latestNonce,
            srcEid: eid,
            sender: _sender,
            dstEid: _params.dstEid,
            receiver: _params.receiver,
            guid: GUID.generate(latestNonce, eid, _sender, _params.dstEid, _params.receiver),
            message: _params.message
        });
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(packet);
        bytes memory payload = PacketV1Codec.encodePayload(packet);
        bytes memory encodedPacket = abi.encodePacked(packetHeader, payload);

        // Emit packet information for DVNs, Executors, and any other offchain infrastructure to only listen
        // for this one event to perform their actions.
        emit ILayerZeroEndpointV2.PacketSent(encodedPacket, _params.options, address(0));
    }

    // q why do we even need the superAssetAdapter the vault can directly handle vault to vault communication right, the superAssetAdapter just takes the asset
    // which was already present in the and that flow is really not needed cause the superasset can just say in the vault, as we withdraw 1:1
    function lzReceive(
        Origin calldata, //_origin,
        bytes32, /*_guid*/
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) public payable override {
        address oftTxCaller = address(this); // for test
        // (address receiverOfUnderlying, uint256 tokensAmount, oftTxCaller) = OFTLogic.decodeMessage(_message);
        (address receiverOfUnderlying, uint256 tokensAmount) = OFTLogic.decodeSubLzMessage(_message);

        if (msg.sender != address(endpoint) || oftTxCaller != address(this)) {
            revert UnAuthorized();
        }

        // todo @dev:test un-comment these for mainnet
        // if (
        //   msg.sender == address(endpoint) &&
        //   _getPeerOrRevert(_origin.srcEid) != _origin.sender
        // ) revert OnlyPeer(_origin.srcEid, _origin.sender);
        address assetToTransfer = underlying;
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(address(this), tokensAmount);
            assetToTransfer = ISuperAsset(underlying).underlying();
        }
        // send rVaultAsset tokens to user if we run short of underlying to transfer
        if (IERC20(assetToTransfer).balanceOf(address(this)) < tokensAmount) {
            super._mint(receiverOfUnderlying, tokensAmount);
        } else {
            IERC20(assetToTransfer).safeTransfer(receiverOfUnderlying, tokensAmount);
        }

        // address superAssetAdapter = provider.getSuperAssetAdapter(); // this will be zero in instances other than superchain one
        // TODO: tabish what does this do exactly.
        // if (msg.sender == address(endpoint)) {
        //     if (_getPeerOrRevert(_origin.srcEid) != _origin.sender) {
        //         revert OnlyPeer(_origin.srcEid, _origin.sender);
        //     }
        // }

        // bug the caller will be on the source chain how can we get the size on the destination chain haha
        // but irrespective of the caller we have to just transfer the underlying cause on the source chain the
        // uint256 caller_codesize;
        // assembly {
        //     caller_codesize := extcodesize(oftTxCaller)
        // }
        // if bridging happened through rvaultasset itself mint rvaultasset equals to tokensAmount to each rvaultasset holder
        // todo:discuss with supercontracts.eth what about proportion of holders amount ?
        // TODO: tabish p1
        // when sending we just burn rVault asset on the source chain if the caller is rVaultAsset
        // bug: this is a bit weird we are double spending we are
        // if (oftTxCaller != address(this)) {
        //     distributeRVaultAsset(tokensAmount); // bug we dont need this our invariant is different
        // } else if (caller_codesize == 0) {
        //     // if the caller is an EOA , mint rVaultAsset only to them
        //     _mint(oftTxCaller, tokensAmount);
        // }

        // if (msg.sender == superAssetAdapter) {
        //     ISuperAsset(underlying).withdraw(receiverOfUnderlying, tokensAmount);
        // } else {
        //     IERC20(underlying).safeTransfer(receiverOfUnderlying, tokensAmount);
        // }

        // if (msg.sender == superAssetAdapter) {

        // }
    }

    function _bridgeUsingSuperTokenBridge(
        uint256 amount,
        address receiverOfUnderlying,
        address _underlyingAsset,
        uint256 toChainId
    ) internal {
        if (toChainId != block.chainid) {
            // TODO: umar so here in repay, the superAsset gets sent to the lendingpool but in the lending pool we are assuming that the
            // rVaultAsset is already there - so this line Router.sol#177 IRVaultAsset(rVaultAsset).bridge(address(lendingPool), debtChainId, amount);
            ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
                _underlyingAsset, receiverOfUnderlying, amount, toChainId
            );
        } else {
            ISuperAsset(_underlyingAsset).burn(receiverOfUnderlying, amount);
        }
    }

    /// @notice also write the invariant for bridging ie. sumof RVaultAsset + sumof underlying (source) = sumof RVaultAsset + sumof underlying (source)
    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external onlyRouter {
        // also then we can remove the onlyRouter call
        _bridge(receiverOfUnderlying, toChainId, amount);
    }

    function _bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) internal {
        // TODO: nice work here taking things in memory 🫡
        // DataTypes.Chain_Cluster_Types sourceType = chainIdToClusterType[block.chainid];
        // DataTypes.Chain_Cluster_Types destinationType = chainIdToClusterType[toChainId];
        // DataTypes.Chain_Cluster_Types super_chain_type = DataTypes.Chain_Cluster_Types.SUPER_CHAIN;
        // DataTypes.Chain_Cluster_Types other_cluster_type = DataTypes.Chain_Cluster_Types.OTHER;

        // if (sourceType == super_chain_type) {
        //     if (destinationType == super_chain_type && isSuperTokenBridgeEnabled) {
        //         _bridgeUsingSuperTokenBridge(amount, receiverOfUnderlying, underlying, toChainId);
        //     } else {
        //         _bridgeCrossCluster(amount, receiverOfUnderlying, toChainId);
        //     }
        // } else if (sourceType == other_cluster_type && destinationType == other_cluster_type) {
        //
        // } else {
        //     revert NonConfiguredCluster(toChainId);
        // }

        DataTypes.Chain_Cluster_Types destinationType = chainIdToClusterType[toChainId];
        if (pool_type == 1) {
            if (destinationType == DataTypes.Chain_Cluster_Types.SUPER_CHAIN && isSuperTokenBridgeEnabled) {
                _bridgeUsingSuperTokenBridge(amount, receiverOfUnderlying, underlying, toChainId);
            } else {
                _bridgeCrossCluster(amount, receiverOfUnderlying, toChainId);
            }
        } else {
            _bridgeCrossCluster(amount, receiverOfUnderlying, toChainId);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Privileged Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Enables or disables the use of the SuperTokenBridge for intra-cluster token bridging
    /// @param mode True to enable, false to disable
    function toggleSuperTokenBridgeEnabled(bool mode) public onlySuperAdmin {
        isSuperTokenBridgeEnabled = mode;
    }

    /// @notice Sets the cluster type for a given chainId
    /// @param chainId The chainId for which to set the cluster type
    /// @param cluster_type The cluster type to set (INTER or INTRA)
    function setChainClusterType(uint256 chainId, DataTypes.Chain_Cluster_Types cluster_type) public onlySuperAdmin {
        chainIdToClusterType[chainId] = cluster_type;
    }

    function setChainPeer(uint32 _eid, bytes32 _peer) public onlySuperAdmin {
        _setPeer(_eid, _peer);
    }

    /// @notice Sets the withdrawal cooldown period
    /// @param _newPeriod The new cooldown period in seconds
    /// @custom:access only SuperAdmin
    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external onlySuperAdmin {
        WITHDRAW_COOL_DOWN_PERIOD = _newPeriod;
    }

    // this function distributes rVaultAsset to all holders
    // and also records the amount that rVaultAsset was distributed
    // function distributeRVaultAsset(uint256 tokensAmount) internal {
    //     for (uint256 i = 0; i < totalRVaultAssetHolders; i++) {
    //         if (!isRVaultAssetHolder[rVaultAssetHolder[i]]) continue;
    //         _mint(rVaultAssetHolder[i], tokensAmount);
    //     }
    // }

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
        // Call the parent contract's transfer function
        bool success = super.transfer(recipient, amount);
        if (success) {
            balances[msg.sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override(ERC20) returns (bool) {
        // Call the parent contract's transferFrom function
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

    /*
    Note that we are not strictly following the ERC4626 standard, as we are maintaing a 1:1 peg of underlying and rvaultasset.
    Here are the design choices:
    - Preview functions will return the passed in value, as we are maintaining a 1:1 peg
    - maxDeposit will return type(uint256).max, as we are allowing unlimited deposits
    - maxMint will return type(uint256).max, as we are allowing unlimited mints
    - maxWithdraw will return the balance of the owner, as they can withdraw all their balance
    - maxRedeem will return the balance of the owner, as they can redeem all their shares
    - convertToAssets will return the passed in value, as we are maintaining a 1:1 peg
    - convertToShares will return the passed in value, as we are maintaining a 1:1 peg
    - mint will mint the passed in value, as we are maintaining a 1:1 peg
    - burn will burn the passed in value, as we are maintaining a 1:1 peg
    */
    // Returns the address of the underlying asset token
    function asset() external view returns (address) {
        return underlying;
    }

    function totalAssets() external view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    // Redeem shares and return assets (1:1 peg)
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares; // 1:1 peg
        withdraw(assets, receiver, owner);
    }

    // Preview and conversion functions as provided earlier
    function previewMint(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
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
}
