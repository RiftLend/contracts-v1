// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract TestERC20 is MockERC20 {
    address owner_;

    error onlyOwner();

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _owner) {
        initialize(_name, _symbol, _decimals);
        owner_ = _owner;
    }

    function mint(address to, uint256 amount) public {
        if (msg.sender != owner_) revert onlyOwner();
        _mint(to, amount);
    }

    function owner() external view returns (address) {
        return owner_;
    }

    receive() external payable {}

    fallback() external payable {}
}
