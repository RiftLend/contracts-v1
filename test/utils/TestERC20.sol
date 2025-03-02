// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestERC20 is Initializable, MockERC20, Ownable {
    constructor(address ownerAddr) Ownable(ownerAddr) {
        _transferOwnership(ownerAddr);
    }

    function initialize(string memory _name, string memory _symbol, uint8 _decimals, address _owner)
        external
        initializer
        onlyOwner
    {
        initialize(_name, _symbol, _decimals);
        _transferOwnership(_owner);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
