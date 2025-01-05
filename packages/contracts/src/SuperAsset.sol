// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";

import {SuperchainERC20} from "./SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {OFT} from "./libraries/helpers/layerzero/OFT.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

contract SuperAsset is OFT, SuperchainERC20 {
    using SafeERC20 for IERC20;

    address public underlying;
    string _name;
    string _symbol;
    uint8 _decimals;

    constructor(address _underlying, address _lzEndpoint, address _delegate, string memory name, string memory symbol)
        OFT(_lzEndpoint, _delegate, IERC20Metadata(_underlying).decimals())
    {
        underlying = _underlying;
        _name = name;
        _symbol = symbol;
        _decimals = IERC20Metadata(_underlying).decimals();
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

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns the decimals places of the token.
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
