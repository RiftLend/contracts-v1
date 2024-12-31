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
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/libs/OptionsBuilder.sol";
import {MessagingFee, MessagingReceipt} from "./libraries/helpers/layerzero/OFTCore.sol";
import {TokensLogic} from "./libraries/logic/TokensLogic.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {SuperAssetAdapter} from "./SuperAssetAdapter.sol";

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

    /// @dev address of underlying asset
    mapping(address user => uint256 balance) public balances;
    /// @dev user balance of underlying
    uint256 public totalBalances;
    /// @dev total balances of underlying

    mapping(address => uint256) public _lastWithdrawalTime;

    /// @dev last user withdrawal time
    uint256 public WITHDRAW_COOL_DOWN_PERIOD = 1 days;
    /// @dev withdrawal cooldown period

    mapping(uint256 => DataTypes.Chain_Cluster_Types) public chainId_cluster_type;

    /// @dev is chainId intra cluter or inter-cluster
    bool public bridgingServiceType;
    /// @dev true - superchain , false - OFT
    uint256 public immutable pool_type;
    /// @dev 1 - OP superchain , 2 - other clusters
    address public immutable underlying_of_superAsset;
    /// @dev Only used when pool_type is 1 (OP Superchain). For other clusters, this remains unset.
    mapping(bytes32 => DataTypes.BungeeBridgeOrder) public bridgeOrders;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Events                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CrossChainBridgeUnderlyingInit(bytes32 orderId, uint256 timestamp);
    event CrossChainBridgeUnderlyingSent(bytes32 orderId, uint256 timestamp);
    event CrossChainBridgeUnderlyingBridged(bytes32, uint256 timestamp);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Errors                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error onlyLpConfiguratorCall();
    error onlySuperAssetAdapterCall();
    error NonConfiguredCluster(uint256 ChainId);
    error OnlyRelayer();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlySuperAssetAdapter() {
        if (provider.getSuperAssetAdapter() != msg.sender) revert onlySuperAssetAdapterCall();
        _;
    }

    modifier onlyRelayer() {
        if (provider.getRelayer() != msg.sender) revert OnlyRelayer();
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
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        deposit(shares, receiver);
        assets = shares;
    }

    /// @notice Deposit underlying and mint shares (1:1 peg)
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        totalBalances += assets;
        balances[receiver] += assets;
        super._mint(receiver, assets);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
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
    /*                           Bridge underlying                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*Why split in three methods ?

      - We need offchain api to get quote data ( not available on smart contract level )
      - Due to sometimes receiving intermediary bridge tokens like htokens/anytokens . More on this here https://docs.bungee.exchange/socket-api/guides/bungee-smart-contract-integration/#3-destination-contract
      - replay protection 
      - elegant flow where order status can be tracked
    */

    // Bridging Step 1:

    /**
     * @notice Initiates the bridging process by creating a bridge order.
     * @dev This function creates a bridge order and emits an event that will be picked up by the relayer.
     * @param destChainId The destination chain ID where the underlying assets will be bridged.
     * @param receiverOfUnderlying The address of the receiver on the destination chain.
     * @param _amount The amount of underlying assets to be bridged.
     * @custom:access public
     */
    function initateBridgeUnderlying(uint256 destChainId, address receiverOfUnderlying, uint256 _amount) public {
        address sender = msg.sender;
        uint256 srcChainId = block.chainid;
        require(destChainId != 0 && receiverOfUnderlying != address(0) && _amount != 0, "Zero Values");
        require(balanceOf(sender) >= _amount, "Insufficient balance");
        bytes32 orderId =
            keccak256(abi.encodePacked(sender, srcChainId, destChainId, block.timestamp, receiverOfUnderlying, _amount));
        // This event will be picked up by relayer
        DataTypes.BungeeBridgeOrder memory order = DataTypes.BungeeBridgeOrder(
            orderId,
            0, /* initiated order */
            sender,
            receiverOfUnderlying,
            srcChainId,
            destChainId,
            block.timestamp,
            _amount
        );

        bridgeOrders[orderId] = order;
        emit CrossChainBridgeUnderlyingInit(orderId, block.timestamp);
    }

    // Bridging Step 2:

    /**
     * @notice Bridges tokens from source chain to destination chain
     * @param bungeeTarget the contract of bungee to initiate the cross chain transfer
     * @param txData The encoded transaction data built by relayer based on the emitted CrossChainBridgeUnderlyingInit event params using
     *   Bungee api off-chain to get a quote https://docs.bungee.exchange/socket-api/guides/bungee-smart-contract-integration/#1-get-quote-from-bungee-api-off-chain
     *     KEY_POINT "The destination address needs to be same as source contract address" ( RVaultAsset ) in tx_data used to get quote
     * @param _bungeeAllowanceTarget the contract that needs to be approved to transfer our funds on our behalf.
     * @param orderId unique identifier to denote bridge orders
     * @custom:access only callable by Relayer
     */
    function bridgeUnderlyingSend(
        address payable bungeeTarget,
        bytes memory txData,
        address _bungeeAllowanceTarget,
        bytes32 orderId
    ) public onlyRelayer {
        // Replay protection
        uint256 amount = bridgeOrders[orderId].amount;

        require(bridgeOrders[orderId].id != bytes32(0), "Order does not exist");
        require(bridgeOrders[orderId].status == 0, "Order Must be in initiated stage");
        bridgeOrders[orderId].status = 1; // take order to "PENDING stage"

        //  The Base asset of the pool is the bottom most in the hierarchy that the pool accepts to operate on.
        // For example , if you see in TokensLogic.getPoolTokenInformation() , on superchain , the baseAsset is superAsset ( and pool type is 1 )
        // and in other clusters , the base asset is the underlying token because there is no SuperAsset on other clusters ( as for now )

        // Using the base asset got from constructor's call to `TokensLogic.getPoolTokenInformation`
        address target_asset = underlying;

        // However , base Asset for OP Superchain ( or the underlying for rVaultAsset) is superAsset.
        // Since on the destination chain , it might not be available , we unwrap it and then send it over bungee api
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(address(this), amount);
            target_asset = underlying_of_superAsset;
        }
        // from this line , the contract has underlying asset unwrapped whether the pool type was op_superchain or any other cluster

        // Here we approve the bungee api contract to transfer our funds.

        IERC20(target_asset).approve(_bungeeAllowanceTarget, amount);
        (bool success,) = bungeeTarget.call(txData);
        require(success, "Bungee Bridging failed");
        emit CrossChainBridgeUnderlyingSent(orderId, block.timestamp);
    }

    // Bridging Step 3:

    /**
     * @notice Completes the bridging process by transferring the underlying tokens to the recipient.
     * @dev This function is the final step in the bridging process. It ensures that the order is in the correct state
     *      and transfers the underlying tokens to the recipient. If the pool type is OP Superchain, it wraps the asset
     *      to SuperAsset before transferring.
     * @param orderId The unique identifier of the bridge order.
     * @custom:access only callable by Relayer
     */
    function withdrawTokens(bytes32 orderId) public onlyRelayer {
        require(bridgeOrders[orderId].status != 2, "Order Already claimed");
        require(bridgeOrders[orderId].status == 1, "Order is Not in Sent Stage");
        bridgeOrders[orderId].status = 2; // take order to "Executed stage"

        uint256 amount = bridgeOrders[orderId].amount;
        address _recepient = bridgeOrders[orderId].receiver;

        if (pool_type == 1) {
            // If on OP_SUPERCHAIN , wrap the asset to superAsset
            IERC20(underlying_of_superAsset).approve(underlying, amount);
            ISuperAsset(underlying).deposit(address(this), amount);
        }
        // at this line , we have the destined underlying asset to transfer to user
        // superAsset ( i.e  superUSDC )if this contract is on op_superchain and plain underlying ( i.e USDC ) if any other cluster

        IERC20(underlying).safeTransfer(_recepient, amount);
    }

    // function bridgeUnderlying(uint256 destChainId, address receiverOfUnderlying, uint256 _amount) external {
    //     // require(
    //     //   _amount <= totalBalances - totalSupply(),
    //     //   'Amount exceeds excess balance'
    //     // );
    //     // //@audit it should be totalSupply() - totalBalances, (when totalSupply() is reduced, totalBalances is also reduced)
    //     // IERC20(underlying).approve(_allowanceTarget, _amount);
    //     // (bool success, ) = _to.call(txData);
    //     // require(success);
    // }

    // no superchain cluster -> superchain cluster
    // vice versa
    function _bridgeCrossCluster(
        uint256 tokensToSend,
        address receiverOfUnderlying,
        address _underlyingAsset,
        uint256 toChainId
    ) internal {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), tokensToSend);

        SuperAssetAdapter superAssetAdapter = SuperAssetAdapter(provider.getSuperAssetAdapter());
        if (pool_type == 1) {
            bytes memory options = "";
            // TODO send this message and then we have to decode it on lzReceive accordingly and give the underlying depending on the type of instance to the user.
            bytes memory message = abi.encode(tokensToSend, receiverOfUnderlying, _underlyingAsset);
            SendParam memory sendParam = SendParam(
                uint32(toChainId),
                bytes32(uint256(uint160(address(this)))),
                tokensToSend,
                tokensToSend, // No Slippage allowed
                "", // empty options
                "", // empty composeMsg
                "" // empty oftCmd
            );
            MessagingFee memory fee = superAssetAdapter.quoteSend(sendParam, false);
            superAssetAdapter.send(sendParam, fee, payable(address(this)));

            // add here revert state if it fails ....
        } else {
            bytes memory options = "";
            // TODO send this message and then we have to decode it on lzReceive accordingly and give the underlying depending on the type of instance to the user.
            bytes memory message = abi.encode(tokensToSend, receiverOfUnderlying, _underlyingAsset);
            SendParam memory sendParam = SendParam(
                uint32(toChainId),
                bytes32(uint256(uint160(address(superAssetAdapter)))),
                tokensToSend,
                tokensToSend, // No Slippage allowed
                "", // empty options
                "", // empty composeMsg
                "" // empty oftCmd
            );
            MessagingFee memory fee = quoteSend(sendParam, false);
            (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
                _send(sendParam, fee, payable(address(this)));
            // add here revert state if it fails ....
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

    // ToDo:q lzReceive should be onlySuperAssetAdapter?

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) public payable override onlySuperAssetAdapter {
        // TODO check here inter or intra 
        // We receive tokens from asset adapter of some other chain

        /// super._lzReceive(_origin, _guid, _message, address(0), _extraData);

        (uint64 tokensAmount, address receiverOfUnderlying, address _underlyingAsset) =
            abi.decode(_message, (uint64, address, address));

        // whether it's a superchain or other cluster type , at this point of the code ,
        // we have wrapped the asset to superAsset if needed . Now let's transfer it to the intended receiver
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(receiverOfUnderlying, tokensAmount);
        } else {
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
            if (bridgingServiceType) {
                _bridgeIntraCluster(amount, receiverOfUnderlying, underlying, toChainId);
            } else {
                _bridgeCrossCluster(amount, receiverOfUnderlying, underlying, toChainId);
            }
        } else {
            revert NonConfiguredCluster(toChainId);
        }
    }

    /**
     *
     *   Priviledged Functions
     */
    function setIntraClusterServiceType(bool mode) public onlySuperAdmin {
        bridgingServiceType = mode;
    }

    function setChainClusterType(uint256 chainId, DataTypes.Chain_Cluster_Types cluster_type) public onlySuperAdmin {
        chainId_cluster_type[chainId] = cluster_type;
    }

    /**
     * @notice Sets the withdrawal cooldown period
     * @param _newPeriod The new cooldown period in seconds
     * @custom:access only SuperAdmin
     */
    function setWithdrawCoolDownPeriod(uint256 _newPeriod) external onlySuperAdmin {
        WITHDRAW_COOL_DOWN_PERIOD = _newPeriod;
    }

    /*
    ERC4626 Vault compliant functions
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
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        return shares;
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        return assets;
    }

    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        return shares;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return assets;
    }

    function maxDeposit(address) external view returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external view returns (uint256) {
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
