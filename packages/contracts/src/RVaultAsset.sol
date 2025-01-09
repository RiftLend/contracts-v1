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
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {SuperAssetAdapter} from "./SuperAssetAdapter.sol";
import {OFTLogic} from "./libraries/logic/OFTLogic.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";

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

    mapping(uint256 => DataTypes.Chain_Cluster_Types) public chainIdToClusterType;

    /// @dev true - superchain , false - OFT

    bool public isSuperTokenBridgeEnabled;
    /// @dev 1 - OP superchain , 2 - other clusters

    uint256 public immutable pool_type;
    /// @dev Only used when pool_type is 1 (OP Superchain). For other clusters, this remains unset.

    address public immutable underlying_of_superAsset;
    /// @dev for saving gas , caching the address
    SuperAssetAdapter superAssetAdapter;

    // For keep record of and distrbuting to all rValtAssetHolders
    // Protection against DOS when there are huge number of rVaultAssetHolders , good to use mappings than arrays
    //todo:discuss with supercontracts.eth on edge cases
    mapping(uint256 => address) internal rVaultAssetHolder;
    mapping(address => bool) internal isRVaultAssetHolder;
    uint256 totalRVaultAssetHolders;

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
    error onlySuperAssetAdapterOrLzEndpointCall();
    error onlyRouterCall();
    error withdrawCoolDownPeriodNotElapsed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlySuperAssetAdapter() {
        if (address(superAssetAdapter) != msg.sender) {
            revert onlySuperAssetAdapterCall();
        }
        _;
    }

    modifier onlyRelayer() {
        if (provider.getRelayer() != msg.sender) revert OnlyRelayerCall();
        _;
    }

    modifier onlyRouter() {
        if (provider.getRouter() != msg.sender) revert onlyRouterCall();
        _;
    }

    modifier onlySuperAssetAdapterOrLzEndpoint() {
        if (address(superAssetAdapter) != msg.sender && address(endpoint) != msg.sender) {
            revert onlySuperAssetAdapterOrLzEndpointCall();
        }
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
        if (pool_type == 1) underlying_of_superAsset = ISuperAsset(underlying).underlying();

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        superAssetAdapter = SuperAssetAdapter(provider.getSuperAssetAdapter());

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

        if (!isRVaultAssetHolder[receiver]) {
            isRVaultAssetHolder[receiver] = true;
            rVaultAssetHolder[totalRVaultAssetHolders++] = receiver;
        }
        return assets;
    }

    /// @notice Burn shares and return underlying
    function burn(address user,address receiverOfUnderlying, uint256 toChainId, uint256 amount) external {
        if (msg.sender !=user) _spendAllowance(user,msg.sender,amount);
        _burn(msg.sender, amount);
        // IERC20(underlying).safeTransfer(msg.sender, address(this), amount);
        _bridge(receiverOfUnderlying, toChainId, amount);
        if (balances[msg.sender] == 0) isRVaultAssetHolder[msg.sender] = false;
    }

    // Withdraw assets and burn shares (1:1 peg)

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        // Check the cooldown period
        if (block.timestamp < _lastWithdrawalTime[owner] + WITHDRAW_COOL_DOWN_PERIOD) {
            revert withdrawCoolDownPeriodNotElapsed();
        }

        shares = assets; // 1:1 peg
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        // Update the last withdrawal time
        _lastWithdrawalTime[owner] = block.timestamp;
        // unwrap underlying from superAsset
        if (pool_type == 1) ISuperAsset(underlying).withdraw(receiver, shares);
        else IERC20(underlying).safeTransfer(receiver, shares);
        return shares;
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

    function _bridgeCrossCluster(uint256 tokensToSend, address receiverOfUnderlying, uint256 toChainId) internal {
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(address(superAssetAdapter), tokensToSend);

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
            // Now there can be two cases , arb-eth cluster to superchain
            // or abrb-eth cluster to arb-eth

            bytes memory compose_message = OFTLogic.encodeMessage(receiverOfUnderlying, tokensToSend);

            SendParam memory sendParam = SendParam(
                uint32(toChainId),
                bytes32(uint256(uint160(address(0)))),
                tokensToSend,
                tokensToSend, // No Slippage
                "", // No options
                compose_message,
                "" // empty oftCmd
            );
            // TODO: u have to check if toChainId this is going to superchain / normal and then pass superAssetAdapter / address(this)
            // decide recipient
            if (chainIdToClusterType[toChainId] == DataTypes.Chain_Cluster_Types.SUPER_CHAIN) {
                sendParam.to = bytes32(uint256(uint160(address(superAssetAdapter))));
            } else {
                sendParam.to = bytes32(uint256(uint160(address(this))));
            }

            MessagingFee memory fee = quoteSend(sendParam, false);
            _send(sendParam, fee, payable(address(this)));
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
        if (msgReceipt.guid == 0 && msgReceipt.nonce == 0) revert OftSendFailed();

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
    ) public payable override onlySuperAssetAdapterOrLzEndpoint {
        if (msg.sender == address(endpoint)) {
            if (_getPeerOrRevert(_origin.srcEid) != _origin.sender) {
                revert OnlyPeer(_origin.srcEid, _origin.sender);
            }
        }

        (address receiverOfUnderlying, uint256 tokensAmount, address oftTxCaller) = OFTLogic.decodeMessage(_message);

        uint256 caller_codesize;
        assembly {
            caller_codesize := extcodesize(oftTxCaller)
        }
        // if bridging happened through rvaultasset itself mint rvaultasset equals to tokensAmount to each rvaultasset holder
        // todo:discuss with supercontracts.eth what about proportion of holders amount ?
        if (oftTxCaller == address(this)) {
            distributeRVaultAsset(tokensAmount);
        } else if (caller_codesize == 0) {
            // if the caller is an EOA , mint rVaultAsset only to them
            _mint(oftTxCaller, tokensAmount);
        }

        if (msg.sender == address(superAssetAdapter)) {
            ISuperAsset(underlying).withdraw(receiverOfUnderlying, tokensAmount);
        } else {
            IERC20(underlying).safeTransfer(receiverOfUnderlying, tokensAmount);
        }
    }

    function _bridgeUsingSuperTokenBridge(
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

    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external onlyRouter {
        _bridge(receiverOfUnderlying, toChainId, amount);
    }

    function _bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) internal {
        DataTypes.Chain_Cluster_Types sourceType = chainIdToClusterType[block.chainid];
        DataTypes.Chain_Cluster_Types destinationType = chainIdToClusterType[toChainId];
        DataTypes.Chain_Cluster_Types super_chain_type = DataTypes.Chain_Cluster_Types.SUPER_CHAIN;
        DataTypes.Chain_Cluster_Types other_cluster_type = DataTypes.Chain_Cluster_Types.OTHER;

        if (sourceType == super_chain_type) {
            if (destinationType == super_chain_type && isSuperTokenBridgeEnabled) {
                _bridgeUsingSuperTokenBridge(amount, receiverOfUnderlying, underlying, toChainId);
            } else {
                _bridgeCrossCluster(amount, receiverOfUnderlying, toChainId);
            }
        } else if (sourceType == other_cluster_type && destinationType == other_cluster_type) {
            _bridgeCrossCluster(amount, receiverOfUnderlying, toChainId);
        } else {
            revert NonConfiguredCluster(toChainId);
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

    /// @notice Sets the withdrawal cooldown period
    /// @param _newPeriod The new cooldown period in seconds
    /// @custom:access only SuperAdmin
    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external onlySuperAdmin {
        WITHDRAW_COOL_DOWN_PERIOD = _newPeriod;
    }

    // this function distributes rVaultAsset to all holders
    // and also records the amount that rVaultAsset was distributed
    function distributeRVaultAsset(uint256 tokensAmount) internal {
        for (uint256 i = 0; i < totalRVaultAssetHolders; i++) {
            if (!isRVaultAssetHolder[rVaultAssetHolder[i]]) continue;
            _mint(rVaultAssetHolder[i], tokensAmount);
        }
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
