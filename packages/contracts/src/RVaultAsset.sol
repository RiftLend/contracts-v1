// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";
import "./interfaces/IRVaultAsset.sol";
import {ISuperchainTokenBridge} from "./interfaces/ISuperchainTokenBridge.sol";
import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";

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

import {Ownable} from "@solady/auth/Ownable.sol";

/// @dev whenever user uses this with SuperchainTokenBridge,
// the destination chain will mint aToken (if underlying < totalBalances)
// and transfer underlying remaining

contract RVaultAsset is SuperOwnable, OFT {
    using SafeERC20 for IERC20;

    ///////////////////////////////////
    ///////////// State Variables /////
    ///////////////////////////////////

    address public underlying; // address of underlying asset
    mapping(address user => uint256 balance) public balances; // user balance of underlying
    uint256 public totalBalances; // total balances of underlying
    ILendingPoolAddressesProvider provider;
    address admin;
    mapping(address => uint256) private _lastWithdrawalTime;
    uint256 public constant WITHDRAW_COOL_DOWN_PERIOD = 1 days;
    mapping(uint256 => DataTypes.Chain_Cluster_Types) public chainId_cluster_type; // is chainId intra cluter or inter-cluster

    uint256 intraClusterBridgingServiceType = 1; // 1 for superchain , 2 for OFT
    uint256 pool_type; // 1 for OP superchain , 2 for other clusters
    // If the chain is superchain , the superAsset has some underlying , we will store that in this variable
    address underlying_of_superAsset;

    mapping(bytes32 => DataTypes.BungeeBridgeOrder) public bridgeOrders;

    ///////////////////////////////
    /////////// Events ////////////
    ///////////////////////////////
    event CrossChainBridgeUnderlyingInit(bytes32 orderId, uint256 timestamp);
    event CrossChainBridgeUnderlyingSent(bytes32 orderId, uint256 timestamp);
    event CrossChainBridgeUnderlyingBridged(bytes32, uint256 timestamp);

    ///////////////////////////////////
    ///////////// Errors //////////////
    ///////////////////////////////////

    error onlyLpConfiguratorCall();
    error onlySuperAssetAdapterCall();
    error NonConfiguredCluster(uint256 ChainId);

    ///////////////////////////////////
    ///////////// Modifiers //////////////
    ///////////////////////////////////

    modifier onlySuperAssetAdapter() {
        if (provider.getSuperAssetAdapter() != msg.sender) {
            revert onlySuperAssetAdapterCall();
        }
        _;
    }

    modifier onlyRelayer() {
        require(provider.getRelayer() == msg.sender, "!relayer");
        _;
    }
    /////////////////////////

    constructor(
        address underlying_,
        ILendingPoolAddressesProvider provider_,
        address admin_,
        address lzEndpoint_,
        address delegate_
    ) OFT(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol(), lzEndpoint_, delegate_) {
        underlying = underlying_;
        (, pool_type,) = TokensLogic.getPoolTokenInformation(provider_);
        underlying_of_superAsset = provider_.getUnderlying();
        provider = provider_;
        admin = admin_;

        _initializeSuperOwner(uint64(block.chainid), admin_);
    }

    /// @dev minting more than totalBalances will mint rToken and transfer underlying
    function _mint(address to_, uint256 amount_) internal {
        if (amount_ > totalBalances) {
            // need to mint more than totalBalances
            balances[to_] += amount_ - totalBalances;
            super._mint(to_, amount_ - totalBalances);
            // reset totalBalances and transfer underlying
            totalBalances = 0;
            IERC20(underlying).safeTransfer(to_, totalBalances);
        } else {
            totalBalances -= amount_;
            IERC20(underlying).safeTransfer(to_, amount_);
        }
    }

    function burn_(address from_, uint256 amount_) internal {
        balances[from_] -= amount_;
        super._burn(from_, amount_);
    }

    function burn(address user, address receiverOfUnderlying, uint256 toChainId, uint256 amount) external {
        super._burn(user, amount);
        bridge(receiverOfUnderlying, toChainId, amount);
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

    function transferFrom(address sender, address recipient, uint256 amount)
        public
        override(ERC20, IERC20)
        returns (bool)
    {
        // Call the parent contract's transferFrom function
        bool success = super.transferFrom(sender, recipient, amount);
        if (success) {
            balances[sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    ///////////////////////////////////
    //////////// Bridge underlying/////
    //////////////////////////////////

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
        uint256 srcChainId = getChainID();
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

    function _bridgeCrossCluster(
        uint256 tokensToSend,
        address receiverOfUnderlying,
        address _underlyingAsset,
        uint256 toChainId
    ) internal {
        // IERC20(underlying).safeTransfer(to, amount);

        bytes memory options = "";

        bytes memory message = abi.encode(tokensToSend, receiverOfUnderlying, _underlyingAsset);

        SendParam memory sendParam = SendParam(
            uint32(toChainId),
            bytes32(uint256(uint160(receiverOfUnderlying))),
            tokensToSend,
            tokensToSend, // No Slippage allowed
            "", // empty options
            "", // empty composeMsg
            "" // empty oftCmd
        );

        SuperAssetAdapter superAssetAdapter = SuperAssetAdapter(provider.getSuperAssetAdapter());
        MessagingFee memory fee = superAssetAdapter.quoteSend(sendParam, false);

        superAssetAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
    }

    // ToDo:q lzReceive should be onlySuperAssetAdapter?

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) public payable override onlySuperAssetAdapter {
        // We receive tokens from asset adapter of some other chain

        (uint64 tokensAmount, address receiverOfUnderlying, address _underlyingAsset) =
            abi.decode(_message, (uint64, address, address));

        if (pool_type == 1) {
            // If the current chain is in op_superchain cluster , wrap plain underlying to superAsset
            IERC20(underlying).approve(underlying, tokensAmount);
            ISuperAsset(underlying).deposit(address(this), tokensAmount);
        }

        // whether it's a superchain or other cluster type , at this point of the code ,
        // we have wrapped the asset to superAsset if needed . Now let's transfer it to the intended receiver
        IERC20(underlying).safeTransfer(receiverOfUnderlying, tokensAmount);

        // super._lzReceive(_origin, _guid, _message, address(0), _extraData);
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

    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) public {
        if (
            chainId_cluster_type[toChainId] == DataTypes.Chain_Cluster_Types.INTER
                && intraClusterBridgingServiceType == 1 //If we want to use SuperChainTokenBridge for intra cluster
        ) {
            _bridgeCrossCluster(amount, receiverOfUnderlying, underlying, toChainId);
        } else if (chainId_cluster_type[toChainId] == DataTypes.Chain_Cluster_Types.INTRA) {
            _bridgeIntraCluster(amount, receiverOfUnderlying, underlying, toChainId);
        } else {
            revert NonConfiguredCluster(toChainId);
        }
    }

    /**
     *
     *   Priviledged Functions
     */
    function setIntraClusterServiceType(uint8 mode) public onlySuperAdmin {
        require(mode == 1 || mode == 2, "InvalidBridgingMode");
        intraClusterBridgingServiceType = mode;
    }

    function setChainClusterType(uint256 chainId, DataTypes.Chain_Cluster_Types cluster_type) public onlySuperAdmin {
        chainId_cluster_type[chainId] = cluster_type;
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
    function asset() public view virtual override returns (address) {
        return underlying;
    }

    // Returns the total managed assets
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
    // Deposit assets and return shares (1:1 peg)

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        shares = assets; // 1:1 peg
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        // it is a super asset now
        totalBalances += assets;
        _mint(receiver, shares);
        return shares;
    }

    // Withdraw assets and burn shares (1:1 peg)
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
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

    // Mint shares and return assets (1:1 peg)
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        deposit(shares, receiver);
        assets = shares;
    }

    // Redeem shares and return assets (1:1 peg)
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        assets = shares; // 1:1 peg
        withdraw(assets, receiver, owner);
    }

    // Preview and conversion functions as provided earlier
    function previewMint(uint256 shares) public view virtual override returns (uint256 assets) {
        return shares;
    }

    function previewDeposit(uint256 assets) public view virtual override returns (uint256 shares) {
        return assets;
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256 assets) {
        return shares;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        return assets;
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    function getChainID() public view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    ////////////////////////////////////////
    ///// Overriding ownable methods //////
    ////////////////////////////////////////
    function _setOwner(address newOwner) internal override(Ownable, SuperOwnable) {
        SuperOwnable._setOwner(newOwner);
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
}
