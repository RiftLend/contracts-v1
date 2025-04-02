// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SuperAssetTestBase} from "./SuperAssetTestBase.t.sol";

contract SuperAssetTestWithdraw is SuperAssetTestBase {
    /// @notice Test that withdrawing from the superasset
    ///         correctly reduces the user's balance and increases
    ///         the user's underlying token balance
    function test_superAssetWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        superAsset.deposit(user1, DEPOSIT_AMOUNT);

        uint256 beforeBalance = IERC20(superAsset.underlying()).balanceOf(user1);

        // Then withdraw
        superAsset.withdraw(user1, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(superAsset.balanceOf(user1), 0, "Withdraw should have reduced user's balance");
        assertEq(
            IERC20(superAsset.underlying()).balanceOf(user1),
            beforeBalance + DEPOSIT_AMOUNT,
            "Withdraw should have increased user's underlying token balance"
        );
    }
    /// @notice Test that the superasset's withdraw function behaves correctly
    /// @notice when given a random amount of tokens to withdraw

    function test_superAssetFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound the amounts to something reasonable
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.startPrank(user1);
        superAsset.deposit(user1, depositAmount);
        superAsset.withdraw(user1, withdrawAmount);
        vm.stopPrank();

        assertEq(
            superAsset.balanceOf(user1), depositAmount - withdrawAmount, "Withdraw should have reduced user's balance"
        );
    }

    /// @notice Test that withdrawing from the superasset
    ///         to another account correctly reduces the user's balance
    ///         and increases the other account's underlying token balance
    function test_superAssetWithdrawToOtherAccount() public {
        // First deposit
        vm.startPrank(user1);
        superAsset.deposit(user1, DEPOSIT_AMOUNT);

        uint256 beforeBalance = IERC20(superAsset.underlying()).balanceOf(user2);

        // Withdraw to user2
        superAsset.withdraw(user2, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(superAsset.balanceOf(user1), 0, "Withdraw should have reduced user's balance");
        assertEq(
            IERC20(superAsset.underlying()).balanceOf(user2),
            beforeBalance + DEPOSIT_AMOUNT,
            "Withdraw should have increased other account's underlying token balance"
        );
    }

    function test_superAssetWithdrawInsufficientBalanceFails() public {
        vm.startPrank(user1);
        vm.expectRevert();
        superAsset.withdraw(user1, 1); // Should fail as user1 has no balance
    }
}
