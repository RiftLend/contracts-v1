// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestERC20 is Initializable, ERC20, Ownable {
    string _name;
    string _symbol;
    uint8 _decimals;

    constructor(address ownerAddr) Ownable(ownerAddr) {
        _transferOwnership(ownerAddr);
    }

    function initialize(string memory name_, string memory symbol_, uint8 decimals_, address owner_)
        external
        initializer
        onlyOwner
    {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _transferOwnership(owner_);
    }

    function mint(address to_, uint256 amount_) public onlyOwner {
        _mint(to_, amount_);
    }

    receive() external payable {}

    fallback() external payable {}

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
