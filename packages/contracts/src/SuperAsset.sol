// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from '@contracts-bedrock/libraries/Predeploys.sol';
import {SuperchainERC20} from '@contracts-bedrock/L2/SuperchainERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol';
import {SuperOwnable} from '@interop-std/auth/SuperOwnable.sol';

import {IERC20} from '@openzeppelin/contracts-v5/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol';

import {ILendingPoolAddressesProvider} from './interfaces/ILendingPoolAddressesProvider.sol';

/// @dev whenever user uses this with SuperchainTokenBridge, the destination chain will mint aToken (if underlying < totalBalances) and transfer underlying remaining
contract SuperAsset is SuperchainERC20 {
  using SafeERC20 for IERC20;
  address public underlying;
  address public constant NATIVE_ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  ILendingPoolAddressesProvider provider;
  string _name;
  string _symbol;
  uint8 _decimals;

  constructor(
    address underlying_,
    ILendingPoolAddressesProvider provider_
      )  {

    underlying = underlying_;
    provider = provider_;
    _name = IERC20Metadata(underlying).name();
    _symbol = IERC20Metadata(underlying).symbol();
    _decimals = IERC20Metadata(underlying).decimals();
    
  }

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

    // #33
  // 1:1 Wrap
  // Allows native ether
  function deposit(address to, uint amount) public  {
      // Get underlying tokens from user
    IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
    
    // Mint at 1:1 ratio
    _mint(msg.sender, amount);
  }

  function withdraw(address to, uint amount) public {
    // Burn user's superAsset
    _burn(msg.sender, amount);
     IERC20(underlying).safeTransfer(to, amount);
    
  }

  receive()external payable{
    deposit(msg.sender,msg.value);
  }
}
