// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "./RVaultAssetTestBase.t.sol";

contract RVaultAssetTestDeposit is RVaultAssetTestBase {
    /**
     * @dev Tests that depositing into the rVaultAsset increases the user's balance and reduces their underlying token balance.
     */
    function test_rVaultAssetDeposit() public {
        address rVaultAssetUnderlying = IRVaultAsset(rVaultAsset1).asset();

        uint256 beforeBalance = IERC20(rVaultAssetUnderlying).balanceOf(user1);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);

        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(rVaultAssetUnderlying).balanceOf(user1), beforeBalance - DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @dev Tests that depositing with a fuzzed amount works correctly.
     */
    function test_rVaultAssetFuzzDeposit(uint256 amount) public {
        amount = bound(amount, 1, DEPOSIT_AMOUNT);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).deposit(amount, user1);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), amount);
    }
}
