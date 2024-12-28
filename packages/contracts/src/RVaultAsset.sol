// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts-v5/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";

/// @dev whenever user uses this with SuperchainTokenBridge,
// the destination chain will mint aToken (if underlying < totalBalances)
// and transfer underlying remaining

contract RVaultAsset is OFT, IERC4626 {
    using SafeERC20 for IERC20;

    address public underlying; // address of underlying asset
    mapping(address user => uint256 balance) public balances; // user balance of underlying
    uint256 public totalBalances; // total balances of underlying
    ILendingPoolAddressesProvider provider;
    address admin;

    modifier onlyLendingPoolConfigurator() {
        require(
            provider.getLendingPoolConfigurator() == msg.sender, "Only lending pool configurator can call this function"
        );
        _;
    }

    // delegate for layerzero OFT is zero address

    constructor(
        address underlying_, // SuperAsset
        ILendingPoolAddressesProvider provider_,
        address admin_,
        address lzEndpoint_,
        address delegate_
    )
        OFT(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol(), lzEndpoint_, delegate_)
        Ownable(delegate_)
    {
        underlying = underlying_;
        provider = provider_;
        admin = admin_;
        // _initializeSuperOwner(uint64(block.chainid), admin_);
    }

    /// @dev minting more than totalBalances will mint aToken and transfer underlying
    /// only callable by SuperchainTokenBridge (which has already burned the aToken amount on source chain)
    function mint_(address to_, uint256 amount_) internal {
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

    function mint(address to_, uint256 amount_) external {
        balances[to_] += amount_;
        totalBalances += amount_;
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount_);
        super._mint(to_, amount_);
    }

    function burn_(address from_, uint256 amount_) internal {
        balances[from_] -= amount_;
        super._burn(from_, amount_);
    }

    function burn(address to_, uint256 amount_) external {
        totalBalances -= amount_;
        _burn(msg.sender, amount_);
        IERC20(underlying).safeTransfer(to_, amount_);
    }

    function transfer(address recipient, uint256 amount) public override(IERC20, ERC20) returns (bool) {
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
        override(IERC20, ERC20)
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

    // TODO write this out completely.
    /// @dev bridge underlying to another chain using bungee api
    function bridgeUnderlying(address payable _to, bytes memory txData, address _allowanceTarget, uint256 _amount)
        external
        onlyLendingPoolConfigurator
    {
        require(_amount <= totalBalances - totalSupply(), "Amount exceeds excess balance");
        //@audit it should be totalSupply() - totalBalances, (when totalSupply() is reduced, totalBalances is also reduced)
        IERC20(underlying).approve(_allowanceTarget, _amount);
        (bool success,) = _to.call(txData);
        require(success);
    }

    /// @dev During bridging, we may receive anyTokens / hTokens if there's not enough underlying
    // therefore we may need to withdraw them and manually swap
    function withdrawTokens(address _token, address _recepient) public onlyLendingPoolConfigurator {
        require(_token != underlying, "Cannot withdraw underlying");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recepient, amount);
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
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return shares;
    }

    // Mint shares and return assets (1:1 peg)
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        assets = shares; // 1:1 peg
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    // Withdraw assets and burn shares (1:1 peg)
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        shares = assets; // 1:1 peg
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);
        return shares;
    }

    // Redeem shares and return assets (1:1 peg)
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        assets = shares; // 1:1 peg
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);
        return assets;
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

    ////////////////////////////////////////
}
