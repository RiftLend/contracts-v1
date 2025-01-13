// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Base} from "../Base.t.sol";

contract SuperAssetTestBase is Base {
    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);

    // Test state variables
    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();

        // Fund users with underlying token
        deal(address(superAsset.underlying()), user1, INITIAL_BALANCE);
        deal(address(superAsset.underlying()), user2, INITIAL_BALANCE);

        // Approve superAsset to spend underlying tokens
        vm.startPrank(user1);
        IERC20(superAsset.underlying()).approve(address(superAsset), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(superAsset.underlying()).approve(address(superAsset), type(uint256).max);
        vm.stopPrank();
    }
}
