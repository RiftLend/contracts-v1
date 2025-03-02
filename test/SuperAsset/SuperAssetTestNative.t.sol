// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SuperAssetTestBase} from "./SuperAssetTestBase.t.sol";
import {SuperAsset} from "src/SuperAsset.sol";

contract SuperAssetTestNative is SuperAssetTestBase {
    /// @notice Test that the superasset receives native tokens and
    ///         updates the user's balance accordingly
    function test_superAssetReceiveNativeToken() public {
        uint256 sendAmount = 1 ether;
        vm.deal(user1, sendAmount);
        vm.prank(user1);
        (bool success,) = address(superAssetWeth).call{value: sendAmount}("");
        assertTrue(success);
        assertEq(superAssetWeth.balanceOf(user1), sendAmount);
    }

    function test_superAssetUnderlyingNotWethReverts() public {
        uint256 sendAmount = 1 ether;
        vm.deal(user1, sendAmount);
        vm.prank(user1);
        vm.expectRevert(SuperAsset.UNDERLYING_NOT_WETH.selector);
        (bool success,) = address(superAsset).call{value: sendAmount}("");
        // Dead code
        require(success, "Failed to send ETH to superAsset");
    }
}
