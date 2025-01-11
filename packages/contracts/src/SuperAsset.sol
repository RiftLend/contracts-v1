// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {SuperchainERC20} from "src/SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Metadata.sol";

contract SuperAsset is SuperchainERC20 {
    using SafeERC20 for IERC20;

    address public underlying;
    string _name;
    string _symbol;
    uint8 _decimals;
    address public WETH;

    constructor(address underlying_, string memory name_, string memory symbol_, address WETH_) {
        underlying = underlying_;
        _name = name_;
        _symbol = symbol_;
        _decimals = IERC20Metadata(underlying_).decimals();
        WETH = WETH_;
    }

    function deposit(address _to, uint256 _amount) external payable {
        if (msg.value == _amount) {
            assembly ("memory-safe") {
                let underlyingAddr := sload(underlying.slot)
                pop(call(gas(), underlyingAddr, callvalue(), codesize(), 0x00, codesize(), 0x00))
            }
        } else {
            IERC20(underlying).safeTransferFrom(msg.sender, address(this), _amount);
        }
        _mint(_to, _amount);
    }

    function withdraw(address _to, uint256 _amount) external {
        _burn(msg.sender, _amount);
        // TODO: cross check weth contracts on all chains we deploy to
        // (sepolia, base, arbitrum, optimism, mainnet, inkchain, unichain, celo)
        if (WETH == underlying) {
            (bool success,) = WETH.call(abi.encodeWithSignature("withdraw(uint256)", _amount));
            require(success, "Withdraw failed");
        } else {
            IERC20(underlying).safeTransfer(_to, _amount);
        }
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

    receive() external payable {
        assembly ("memory-safe") {
            let underlyingAddr := sload(underlying.slot)
            pop(call(gas(), underlyingAddr, callvalue(), codesize(), 0x00, codesize(), 0x00))
        }
        _mint(msg.sender, msg.value);
    }
}
