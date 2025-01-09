// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Base} from "../Base.t.sol";

contract SuperAssetTest is Base {
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

    function testFail_superAssetWithdrawInsufficientBalance() public {
        vm.startPrank(user1);
        superAsset.withdraw(user1, 1); // Should fail as user1 has no balance
        vm.stopPrank();
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
}
