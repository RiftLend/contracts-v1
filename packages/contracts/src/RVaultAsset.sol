// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";
import {ERC4626} from "@openzeppelin/contracts-v5/token/ERC20/extensions/ERC4626.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @dev whenever user uses this with SuperchainTokenBridge, the destination chain will mint aToken (if underlying < totalBalances) and transfer underlying remaining
contract RVaultAsset is ERC4626, OFT {
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address public underlying; // address of underlying asset
    mapping(address user => uint256 balance) public balances; // user balance of underlying
    uint256 public totalBalances; // total balances of underlying
    ILendingPoolAddressesProvider public immutable provider;

    modifier onlyLendingPoolConfigurator() {
        require(
            provider.getLendingPoolConfigurator() == msg.sender, "Only lending pool configurator can call this function"
        );
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address underlying_, // SuperAsset
        ILendingPoolAddressesProvider provider_,
        address admin_,
        address lzEndpoint_,
        address delegate_
    ) ERC4626(IERC20(underlying_)) OFT(name_, symbol_, lzEndpoint_, delegate_) Ownable(delegate_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        underlying = underlying_;
        provider = provider_;
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

    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return _decimals;
    }
}
