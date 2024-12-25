// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";

contract SuperAsset is OFT, SuperchainERC20 {
    using SafeERC20 for IERC20;

    address public underlying;
    address address_zero;

    constructor(address underlying_, address _lzEndpoint)
        OFT(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol(), _lzEndpoint, address_zero)
        Ownable(address_zero)
        SuperchainERC20(IERC20Metadata(underlying_).name(), IERC20Metadata(underlying_).symbol())
    {
        underlying = underlying_;
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
        assembly ("memory-safe") {
            // Load underlying address from storage slot 0
            let underlyingAddr := sload(underlying.slot)
            pop(call(gas(), underlyingAddr, callvalue(), codesize(), 0x00, codesize(), 0x00))
        }
        deposit(msg.sender, msg.value);
    }
}
