// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "./RVaultAssetTestBase.t.sol";

contract RVaultAssetTestWithdraw is RVaultAssetTestBase {
    /**
     * @dev Tests that withdrawals from the rVaultAsset are only allowed after a cooldown period has passed.
     */
    function test_rVaultAssetWithdrawWithCooldown() public {
        // First deposit
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);

        // First withdrawal should work
        uint256 beforeBalance_underlying = IERC20(underlyingAsset).balanceOf(user1);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);

        // Verify first withdrawal
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT / 2);
        assertEq(IERC20(underlyingAsset).balanceOf(user1), beforeBalance_underlying + DEPOSIT_AMOUNT / 2);

        // Immediate second withdrawal should fail
        vm.startPrank(user1);
        vm.expectRevert();
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);
        vm.stopPrank();
        // After cooldown period, withdrawal should succeed
        vm.warp(block.timestamp + IRVaultAsset(rVaultAsset1).withdrawCoolDownPeriod() + 1);
        vm.startPrank(user1);
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);
        vm.stopPrank();

        // Verify final state
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), 0);
        assertEq(IERC20(underlyingAsset).balanceOf(user1), beforeBalance_underlying + DEPOSIT_AMOUNT);

        vm.stopPrank();
    }
    /**
     * @dev Tests that withdrawing with a fuzzed amount works correctly.
     */

    function test_rVaultAssetFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, DEPOSIT_AMOUNT);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).deposit(depositAmount, user1);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).withdraw(withdrawAmount, user1, user1);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), depositAmount - withdrawAmount);
    }
}
