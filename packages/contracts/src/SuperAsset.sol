// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";

import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

contract SuperAsset is OFT, SuperchainERC20 {
    using SafeERC20 for IERC20;

    address public underlying;

    constructor(address _underlying, address _lzEndpoint, address _delegate, string memory _name, string memory _symbol)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {
        underlying = _underlying;
    }

    function deposit(address _to, uint256 _amount) public {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(_to, _amount);
    }

    function withdraw(address _to, uint256 _amount) external {
        _burn(msg.sender, _amount);
        IERC20(underlying).safeTransfer(_to, _amount);
    }

    receive() external payable {
        assembly ("memory-safe") {
            let underlyingAddr := sload(underlying.slot)
            pop(call(gas(), underlyingAddr, callvalue(), codesize(), 0x00, codesize(), 0x00))
        }
        deposit(msg.sender, msg.value);
    }
}
