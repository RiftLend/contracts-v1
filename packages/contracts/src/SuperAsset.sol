// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {SuperOwnable} from "./interop-std/src/auth/SuperOwnable.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract SuperAsset is OFT, SuperchainERC20 {
    using SafeERC20 for IERC20;

    address public underlying;
    address public constant NATIVE_ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ILendingPoolAddressesProvider provider;
    uint8 _decimals;

    constructor(address underlying_, ILendingPoolAddressesProvider provider_, address _lzEndpoint, address _delegate)
        OFT(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol(), _lzEndpoint, _delegate)
        Ownable(_delegate)
        SuperchainERC20(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol())
    {
        underlying = underlying_;
        provider = provider_;
        _decimals = uint8(IERC20Metadata(underlying_).decimals());
    }

    function deposit(address to, uint256 amount) public {
        // Get underlying tokens from user
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        // Mint at 1:1 ratio
        _mint(to, amount);
    }

    function withdraw(address to, uint256 amount) external {
        // Burn user's superAsset
        _burn(msg.sender, amount);

        IERC20(underlying).safeTransfer(to, amount);
    }

    receive() external payable {
        deposit(msg.sender, msg.value);
    }
}
