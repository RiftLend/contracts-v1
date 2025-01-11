// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SuperAssetTestBase} from "./SuperAssetTestBase.t.sol";

contract SuperAssetTestNative is SuperAssetTestBase {
    /// @notice Test that the superasset receives native tokens and
    ///         updates the user's balance accordingly
    function test_superAssetReceiveNativeToken() public {
        uint256 sendAmount = 1 ether;
        vm.deal(user1, sendAmount);
        vm.startPrank(user1);
        (bool success,) = address(superAssetWeth).call{value: sendAmount}("");
        vm.stopPrank();

        assertTrue(success);
        assertEq(superAssetWeth.balanceOf(user1), sendAmount);
    }
}
