// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SuperAssetTestBase} from "./SuperAssetTestBase.t.sol";

contract SuperAssetTestDeposit is SuperAssetTestBase {
    /// @notice Test that depositing tokens into the superasset
    ///         correctly increases the user's balance and reduces
    ///         the user's underlying token balance
    function test_superAssetDeposit() public {
        uint256 beforeBalance = IERC20(superAsset.underlying()).balanceOf(user1);

        vm.startPrank(user1);
        superAsset.deposit(user1, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(superAsset.balanceOf(user1), DEPOSIT_AMOUNT, "Deposit should have increased user's balance");
        assertEq(
            IERC20(superAsset.underlying()).balanceOf(user1),
            beforeBalance - DEPOSIT_AMOUNT,
            "Deposit should have reduced user's underlying token balance"
        );
    }

    /// @notice Test that depositing tokens into the superasset
    ///         to another account correctly increases the other account's
    ///         balance and reduces the user's underlying token balance
    function test_superAssetDepositToOtherAccount() public {
        uint256 beforeBalance = IERC20(superAsset.underlying()).balanceOf(user1);

        vm.startPrank(user1);
        superAsset.deposit(user2, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(superAsset.balanceOf(user2), DEPOSIT_AMOUNT, "Deposit should have increased other account's balance");
        assertEq(superAsset.balanceOf(user1), 0, "Deposit should not have increased user's balance");
        assertEq(
            IERC20(superAsset.underlying()).balanceOf(user1),
            beforeBalance - DEPOSIT_AMOUNT,
            "Deposit should have reduced user's underlying token balance"
        );
    }

    function testFail_superAssetDepositInsufficientApproval() public {
        // Remove approval
        vm.startPrank(user1);
        IERC20(superAsset.underlying()).approve(address(superAsset), 0);
        superAsset.deposit(user1, DEPOSIT_AMOUNT); // Should fail due to no approval
        vm.stopPrank();
    }

    function testFail_superAssetDepositInsufficientBalance() public {
        vm.startPrank(user1);
        superAsset.deposit(user1, INITIAL_BALANCE + 1); // Should fail as user doesn't have this much
        vm.stopPrank();
    }

    /// @notice Test that the superasset's deposit function behaves correctly
    ///         when given a random amount of tokens to deposit
    function test_superAssetFuzzDeposit(uint256 amount) public {
        // Bound the amount to something reasonable
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.startPrank(user1);
        superAsset.deposit(user1, amount);
        vm.stopPrank();

        assertEq(superAsset.balanceOf(user1), amount, "Deposit should have increased user's balance");
    }
}
