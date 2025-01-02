// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";
import "./interfaces/IRVaultAsset.sol";
import {ISuperchainTokenBridge} from "./interfaces/ISuperchainTokenBridge.sol";
import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";

import {Ownable} from "@solady/auth/Ownable.sol";
import {Predeploys} from "./libraries/Predeploys.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "./libraries/helpers/layerzero/OFT.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {SendParam, OFTReceipt} from "./libraries/helpers/layerzero/IOFT.sol";
import {MessagingFee} from "./libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {TokensLogic} from "./libraries/logic/TokensLogic.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {SuperAssetAdapter} from "./SuperAssetAdapter.sol";
import {OFTLogic} from "./libraries/logic/OFTLogic.sol";

contract RVaultAsset is SuperOwnable, OFT {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ILendingPoolAddressesProvider provider;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    /// @dev address of underlying asset

    address public immutable underlying;

    /// @dev user balance of underlying

    mapping(address user => uint256 balance) public balances;
    /// @dev total balances of underlying

    uint256 public totalBalances;
    /// @dev last user withdrawal time
    mapping(address => uint256) public _lastWithdrawalTime;

    /// @dev withdrawal cooldown period

    uint256 public WITHDRAW_COOL_DOWN_PERIOD = 1 days;
    /// @dev is chainId intra cluter or inter-cluster

    mapping(uint256 => DataTypes.Chain_Cluster_Types) public chainId_cluster_type;

    /// @dev true - superchain , false - OFT

    bool public isSuperTokenBridgeEnabled;
    /// @dev 1 - OP superchain , 2 - other clusters

    uint256 public immutable pool_type;
    /// @dev Only used when pool_type is 1 (OP Superchain). For other clusters, this remains unset.

    address public immutable underlying_of_superAsset;
    /// @dev for saving gas , caching the address
    SuperAssetAdapter superAssetAdapter;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Events                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CrossChainBridgeUnderlyingSent(bytes txData, uint256 timestamp);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Errors                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error onlySuperAssetAdapterCall();
    error NonConfiguredCluster(uint256 ChainId);
    error OnlyRelayerCall();
    error BridgeCrossClusterFailed();
    error OftSendFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlySuperAssetAdapter() {
        if (provider.getSuperAssetAdapter() != msg.sender) {
            revert onlySuperAssetAdapterCall();
        }
        _;
    }

    modifier onlyRelayer() {
        if (provider.getRelayer() != msg.sender) revert OnlyRelayerCall();
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
    ) OFT(lzEndpoint_, delegate_) {
        underlying = underlying_;
        (, pool_type,) = TokensLogic.getPoolTokenInformation(provider_);
        if (pool_type == 1) underlying_of_superAsset = provider_.getSuperAsset();
        provider = provider_;

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        superAssetAdapter = SuperAssetAdapter(provider.getSuperAssetAdapter());

        _initializeSuperOwner(uint64(block.chainid), msg.sender);
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

    function completeOwnershipHandover(address pendingOwner) public payable override(SuperOwnable, Ownable) {
        SuperOwnable.completeOwnershipHandover(pendingOwner);
    }

    function renounceOwnership() public payable override(SuperOwnable, Ownable) {
        SuperOwnable.renounceOwnership();
    }

    function transferOwnership(address newOwner) public payable override(SuperOwnable, Ownable) {
        SuperOwnable.transferOwnership(newOwner);
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
    }

    /// @notice Burn shares and return underlying
    function burn(address user, address receiverOfUnderlying, uint256 toChainId, uint256 amount) external {
        super._burn(user, amount);
        _bridge(receiverOfUnderlying, toChainId, amount);
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
    /*                           Bridge underlying                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function bridgeUnderlying(
        address payable _bungeeTarget,
        bytes memory txData,
        address _bungeeAllowanceTarget,
        uint256 _underlyingAmount
    ) external onlySuperAdmin {
        address target_asset = underlying;
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(address(this), _underlyingAmount);
            target_asset = underlying_of_superAsset;
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

    function _bridgeCrossCluster(
        uint256 tokensToSend,
        address receiverOfUnderlying,
        address, /*_underlyingAsset*/
        uint256 toChainId
    ) internal {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), tokensToSend);

        if (pool_type == 1) {
            bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, tokensToSend);

            SendParam memory sendParam = SendParam(
                uint32(toChainId),
                bytes32(uint256(uint160(address(this)))),
                tokensToSend,
                tokensToSend, // No Slippage allod
                "",
                compose_message, //  composeMsg
                ""
            );
            MessagingFee memory fee = superAssetAdapter.quoteSend(sendParam, false);
            (MessagingReceipt memory msgReceipt,) = superAssetAdapter.send(sendParam, fee, payable(address(this)));
            if (msgReceipt.guid == 0 && msgReceipt.nonce == 0) revert OftSendFailed();
        } else {
            bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, tokensToSend);
            SendParam memory sendParam = SendParam(
                uint32(toChainId),
                bytes32(uint256(uint160(address(superAssetAdapter)))),
                tokensToSend,
                tokensToSend, // No Slippage
                "", // No options
                compose_message,
                "" // empty oftCmd
            );
            MessagingFee memory fee = quoteSend(sendParam, false);
            _send(sendParam, fee, payable(address(this)));

            // revert case will be handled in _send()
        }
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
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    function lzReceive(
        Origin calldata _origin,
        bytes32, /*_guid*/
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) public payable override {
        // Ensures that only the endpoint can attempt to lzReceive() messages to this OApp.
        if (address(endpoint) != msg.sender) revert OnlyEndpoint(msg.sender);

        // Ensure that the sender matches the expected peer for the source endpoint.
        if (_getPeerOrRevert(_origin.srcEid) != _origin.sender) revert OnlyPeer(_origin.srcEid, _origin.sender);

        (address receiverOfUnderlying, uint256 tokensAmount) = OFTLogic.decodeMessage(_message);

        /* Check here inter or intra
              if msg.sender is superassetadapter , cross cluster - other cluster to superchain
              else intra-cluster
                   - arb-eth cluster
                   - op superchains ( op chain_a to op chain_b)
        */

        if (msg.sender == address(superAssetAdapter)) {
            // arbETH->superchain
            if (pool_type == 1) {
                ISuperAsset(underlying).withdraw(receiverOfUnderlying, tokensAmount);
            }
            // arb->eth
            else {
                IERC20(underlying).safeTransfer(receiverOfUnderlying, tokensAmount);
            }
        }
        // Intra clusters ( superchain to superchain or arb->eth cluster)
        else {
            IERC20(underlying).safeTransfer(receiverOfUnderlying, tokensAmount);
        }
    }

    function _bridgeIntraCluster(
        uint256 amount,
        address receiverOfUnderlying,
        address _underlyingAsset,
        uint256 toChainId
    ) internal {
        if (toChainId != block.chainid) {
            ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
                _underlyingAsset, receiverOfUnderlying, amount, toChainId
            );
        } else {
            ISuperAsset(_underlyingAsset).burn(receiverOfUnderlying, amount);
        }
    }

    function _bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) internal {
        if (chainId_cluster_type[toChainId] == DataTypes.Chain_Cluster_Types.INTER) {
            _bridgeCrossCluster(amount, receiverOfUnderlying, underlying, toChainId);
        } else if (chainId_cluster_type[toChainId] == DataTypes.Chain_Cluster_Types.INTRA) {
            if (isSuperTokenBridgeEnabled) {
                _bridgeIntraCluster(amount, receiverOfUnderlying, underlying, toChainId);
            } else {
                _bridgeCrossCluster(amount, receiverOfUnderlying, underlying, toChainId);
            }
        } else {
            revert NonConfiguredCluster(toChainId);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Privileged Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Enables or disables the use of the SuperTokenBridge for intra-cluster token bridging
    /// @param mode True to enable, false to disable
    function setIntraClusterServiceType(bool mode) public onlySuperAdmin {
        isSuperTokenBridgeEnabled = mode;
    }

    /// @notice Sets the cluster type for a given chainId
    /// @param chainId The chainId for which to set the cluster type
    /// @param cluster_type The cluster type to set (INTER or INTRA)
    function setChainClusterType(uint256 chainId, DataTypes.Chain_Cluster_Types cluster_type) public onlySuperAdmin {
        chainId_cluster_type[chainId] = cluster_type;
    }

    /// @notice Sets the withdrawal cooldown period
    /// @param _newPeriod The new cooldown period in seconds
    /// @custom:access only SuperAdmin
    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external onlySuperAdmin {
        WITHDRAW_COOL_DOWN_PERIOD = _newPeriod;
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

    // Withdraw assets and burn shares (1:1 peg)
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        // Check the cooldown period
        require(
            block.timestamp >= _lastWithdrawalTime[owner] + WITHDRAW_COOL_DOWN_PERIOD,
            "Withdrawal cooldown period not Passed"
        );

        shares = assets; // 1:1 peg
        _spendAllowance(owner, msg.sender, assets);
        _burn(owner, shares);
        // Update the last withdrawal time
        _lastWithdrawalTime[owner] = block.timestamp;

        if (pool_type == 1) {
            // unwrap underlying from superAsset
            ISuperAsset(underlying_of_superAsset).withdraw(address(this), shares);
        }

        // Tranfer assets to receiver
        IERC20(underlying).safeTransfer(receiver, assets);

        return shares;
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

    function burn_(address from_, uint256 amount_) internal {
        balances[from_] -= amount_;
        super._burn(from_, amount_);
    }
}
