// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from '@openzeppelin/contracts-v5/token/ERC20/IERC20.sol';
import {IERC4626} from '@openzeppelin/contracts-v5/interfaces/IERC4626.sol';
import {IERC20Metadata} from '@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol';
import {ILendingPoolAddressesProvider} from './interfaces/ILendingPoolAddressesProvider.sol';
import {ISuperAsset} from './interfaces/ISuperAsset.sol';

import {Predeploys} from './libraries/Predeploys.sol';
import {SafeERC20} from '@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol';
import {OFT} from './libraries/helpers/layerzero/OFT.sol';
import {ERC20} from '@openzeppelin/contracts-v5/token/ERC20/ERC20.sol';
import {SendParam, OFTReceipt} from './libraries/helpers/layerzero/IOFT.sol';
import {OptionsBuilder} from '@layerzerolabs/oapp-evm/libs/OptionsBuilder.sol';
import {MessagingFee, MessagingReceipt} from './libraries/helpers/layerzero/OFTCore.sol';
import {TokensLogic} from "./libraries/logic/TokensLogic.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/// @dev whenever user uses this with SuperchainTokenBridge,
// the destination chain will mint aToken (if underlying < totalBalances)
// and transfer underlying remaining

contract RVaultAsset is SuperOwnable, OFT, IERC4626 {
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

  ///////////////////////////////////
  ///////////// Errors //////////////
  ///////////////////////////////////

  // error InvalidAsset();
  error onlyLpConfiguratorCall();
  error onlySuperAssetAdapterCall();

  ///////////////////////////////////
  ///////////// Modifiers //////////////
  ///////////////////////////////////

  modifier onlyLendingPoolConfigurator() {
    require(
      provider.getLendingPoolConfigurator() == msg.sender,
      onlyLpConfiguratorCall
    );
    _;
  }
  modifier onlySuperAssetAdapter() {
    require(
      provider.getSuperAssetAdapter() == msg.sender,
      onlySuperAssetAdapterCall
    );
  }

  /////////////////////////

  constructor(
    ILendingPoolAddressesProvider provider_,
    address admin_,
    address lzEndpoint_,
    address delegate_
  ) OFT(
      IERC20Metadata(underlying_).name(),
      IERC20Metadata(underlying_).symbol(),
      lzEndpoint_,
      delegate_
    )
  {
    // ToDo:q are we handling it correctly ?
    (,,underlying) = TokensLogic.getPoolTokenInformation(provider_);
    provider = provider_;
    admin = admin_;

    _initializeSuperOwner(uint64(block.chainid), admin_);
  }

  /// @dev minting more than totalBalances will mint rToken and transfer underlying

  function _mint(address to_, uint256 amount_) internal override {
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

  function burn(address user,address receiverOfUnderlying,uint256 toChainId,uint256 amount) external {
    super._burn(user,amount);
    
    bridge(receiverOfUnderlying,toChainId, amount);
    
  }

  function transfer(
    address recipient,
    uint256 amount
  ) public override(IERC20, ERC20) returns (bool) {
    // Call the parent contract's transfer function
    bool success = super.transfer(recipient, amount);
    if (success) {
      balances[msg.sender] -= amount;
      balances[recipient] += amount;
    }
    return success;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public override(IERC20, ERC20) returns (bool) {
    // Call the parent contract's transferFrom function
    bool success = super.transferFrom(sender, recipient, amount);
    if (success) {
      balances[sender] -= amount;
      balances[recipient] += amount;
    }
    return success;
  }

  // TODO write this out completely.
  /// @dev bridge underlying to another chain using bungee api
  function bridgeUnderlying(
    address payable _to,
    bytes memory txData,
    address _allowanceTarget,
    uint256 _amount
  ) external onlyLendingPoolConfigurator {
    
    // require(
    //   _amount <= totalBalances - totalSupply(),
    //   'Amount exceeds excess balance'
    // );
    // //@audit it should be totalSupply() - totalBalances, (when totalSupply() is reduced, totalBalances is also reduced)
    // IERC20(underlying).approve(_allowanceTarget, _amount);
    // (bool success, ) = _to.call(txData);
    // require(success);
    
  }


  function _bridgeCrossCluster(
    uint256 tokensToSend,
    address receiverOfUnderlying,
    address _underlyingAsset,
    uint256 toChainId
  ) internal {

    // IERC20(underlying).safeTransfer(to, amount);

    bytes memory options = '';

    bytes memory message = OFTComposeMsgCodec.encode(
      tokensToSend,
      receiverOfUnderlying,
      _underlyingAsset
    );

    SendParam memory sendParam = SendParam(
      uint32(toChainId),
      bytes32(uint256(uint160(receiverOfUnderlying))),
      tokensToSend,
      tokensToSend, // No Slippage allowed
      // ToDo : should we allow slippage ? (tokensToSend * 9_900) / 10_000, // allow 1% slippage
      '', // empty options
      '', // empty composeMsg
      '' // empty oftCmd
    );

    address superAssetAdapter = provider.getSuperAssetAdapter();
    MessagingFee memory fee = ISuperAssetAdapter(superAssetAdapter).quoteSend(
      sendParam,
      false
    );

    (
      MessagingReceipt memory msgReceipt,
      OFTReceipt memory oftReceipt
    ) = ISuperAssetAdapter(superAssetAdapter).send{value: fee.nativeFee}(
        sendParam,
        fee,
        payable(address(this))
      );
  }

function lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
  ) public payable onlySuperAssetAdapter {

    (
      uint64 tokensToSend,
      address receiverOfUnderlying,
      address _underlyingAsset
    ) = decodeOFTComposeMsgCodec(message);

    _credit(receiverOfUnderlying, tokensToSend);
    super._lzReceive(_origin, _guid, _message, address(0), '');
  }


  function _bridgeIntraCluster(
    uint256 amount,
    address receiverOfUnderlying,
    address _underlyingAsset,
    uint256 toChainId
  ) internal {
    if (toChainId != block.chainid) {
      ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
        _underlyingAsset,
        receiverOfUnderlying,
        amount,
        toChainId
      );
    } else {
      ISuperAsset(_underlyingAsset).burn(receiverOfUnderlying, amount);
    }
  }

  function bridge(
    address receiverOfUnderlying,
    uint256 toChainId,
    uint256 amount
    
  ) public  {
    (,,address baseAsset)=TokensLogic.getPoolTokenInformation(provider_);

    if (
      pool.chainId_cluster_type(toChainId) ==
      DataTypes.Chain_Cluster_Types.INTER
    ) {
      _bridgeCrossCluster(
        amount,
        receiverOfUnderlying,
        baseAsset,
        toChainId
      );
    } else if (
      pool.chainId_cluster_type(toChainId) ==
      DataTypes.Chain_Cluster_Types.INTRA
    ) {
      _bridgeIntraCluster(
        amount,
        receiverOfUnderlying,
        baseAsset,
        toChainId
      );
    } else {
      revert NonConfiguredCluster(toChainId);
    }
  }


  function decodeOFTComposeMsgCodec(
    bytes calldata message
  )
    public
    pure
    returns (
      uint64 tokensToSend,
      address receiverOfUnderlying,
      address _underlyingAsset
    )
  {
    tokensToSend = OFTComposeMsgCodec.tokensToSend(message);
    receiverOfUnderlying = OFTComposeMsgCodec.receiverOfUnderlying(message);
    _underlyingAsset = OFTComposeMsgCodec._underlyingAsset(message);
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

  function deposit(
    uint256 assets,
    address receiver
  ) public virtual override returns (uint256 shares) {
    shares = assets; // 1:1 peg     
    IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
    // it is a super asset now
    totalBalances += assets;
    _mint(receiver, shares);
    return shares;
  }

  /// @dev During bridging, we may receive anyTokens / hTokens if there's not enough underlying
  // therefore we may need to withdraw them and manually swap
  // Withdraw assets and burn shares (1:1 peg)
  //@inheritdoc IERC4626
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) public virtual override returns (uint256 shares) {
    // Check the cooldown period
    require(
      block.timestamp >= _lastWithdrawalTime[owner] + WITHDRAW_COOL_DOWN_PERIOD,
      'Withdrawal cooldown period not Passed'
    );

    shares = assets; // 1:1 peg
    _spendAllowance(owner, msg.sender, assets);
    _burn(owner, shares);
    // Update the last withdrawal time
    _lastWithdrawalTime[owner] = block.timestamp;

    if (underlying == pool_superAsset) {
      // unwrap underlying from superAsset
      ISuperAsset(pool_superAsset).withdraw(receiver, shares);
    }

    IERC20(pool_underlyingAsset).safeTransfer(receiver, assets);

    return shares;
  }

  // Mint shares and return assets (1:1 peg)
  function mint(
    uint256 shares,
    address receiver
  ) public virtual override returns (uint256 assets) {
    deposit(shares, receiver);
    assets = shares;
  }

  // Redeem shares and return assets (1:1 peg)
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override returns (uint256 assets) {
    assets = shares; // 1:1 peg
    withdraw(assets, receiver, owner);
  }

  // Preview and conversion functions as provided earlier
  function previewMint(
    uint256 shares
  ) public view virtual override returns (uint256 assets) {
    return shares;
  }

  function previewDeposit(
    uint256 assets
  ) public view virtual override returns (uint256 shares) {
    return assets;
  }

  function previewWithdraw(
    uint256 assets
  ) public view virtual override returns (uint256 shares) {
    return assets;
  }

  function previewRedeem(
    uint256 shares
  ) public view virtual override returns (uint256 assets) {
    return shares;
  }

  function convertToAssets(
    uint256 shares
  ) public view virtual override returns (uint256 assets) {
    return shares;
  }

  function convertToShares(
    uint256 assets
  ) public view virtual override returns (uint256 shares) {
    return assets;
  }

  function maxDeposit(address) public view virtual override returns (uint256) {
    return type(uint256).max;
  }

  function maxMint(address) public view virtual override returns (uint256) {
    return type(uint256).max;
  }

  function maxWithdraw(
    address owner
  ) public view virtual override returns (uint256) {
    return balanceOf(owner);
  }

  function maxRedeem(
    address owner
  ) public view virtual override returns (uint256) {
    return balanceOf(owner);
  }

  ////////////////////////////////////////
}
