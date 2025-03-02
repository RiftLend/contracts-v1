// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "./RVaultAssetTestBase.t.sol";

contract RVaultAssetTestMisc is RVaultAssetTestBase {
    /**
     * @dev Tests that transfers and balance tracking work correctly.
     */
    function test_rVaultAssetTransferAndBalanceTracking() public {
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        IERC20(rVaultAsset1).transfer(user2, DEPOSIT_AMOUNT / 2);

        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT / 2);
        assertEq(IERC20(rVaultAsset1).balanceOf(user2), DEPOSIT_AMOUNT / 2);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT / 2);
        assertEq(IERC20(rVaultAsset1).balanceOf(user2), DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
    }

    /**
     * @dev Tests that only the super admin can modify the rVaultAsset's state.
     */
    function test_rVaultAssetSuperAdminFunctions() public {
        vm.startPrank(proxyAdmin);
        // Test withdrawal cooldown period modification
        uint256 newPeriod = 2 days;
        IRVaultAsset(rVaultAsset1).setWithdrawCoolDownPeriod(newPeriod);
        assertEq(IRVaultAsset(rVaultAsset1).withdrawCoolDownPeriod(), newPeriod);
        vm.stopPrank();
    }

    /**
     * @dev Tests that non-admins cannot modify the rVaultAsset's state.
     */
    function testFail_rVaultAssetNonAdminFunctions() public {
        vm.startPrank(user1);
        vm.expectRevert();
        IRVaultAsset(rVaultAsset1).setWithdrawCoolDownPeriod(2 days);
        vm.stopPrank();
    }

    /// @dev tests that the rVaultAsset has the correct underlying
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset1 the underlying is superasset
    function test_rVaultAssetUnderlyingIsCorrect() public view {
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset1).asset(), address(superAsset));
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset2).asset(), address(underlyingAsset));
    }

    /// @dev tests that the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset2 the underlying is superasset
    function test_rVaultAssetMintBurnCorrectly() public {
        // for rVaultAsset1 the underlying is superasset
        vm.prank(user1);
        IERC20(address(underlyingAsset)).approve(address(superAsset), 10 ether);
        vm.prank(user1);
        superAsset.deposit(user1, 10 ether);

        uint256 user1SuperAssetBalanceBefore = IERC20(address(superAsset)).balanceOf(user1);

        vm.prank(user1);
        IERC20(address(superAsset)).approve(address(rVaultAsset1), 10 ether);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).mint(10 ether, user1);

        uint256 user1SuperAssetBalanceAfter = IERC20(address(superAsset)).balanceOf(user1);

        assert(IERC20(rVaultAsset1).balanceOf(user1) == 10 ether);
        assert(user1SuperAssetBalanceAfter == user1SuperAssetBalanceBefore - 10 ether);

        // for rVaultAsset2 the underlying is superasset

        uint256 user1UnderlyingBalanceBefore = underlyingAsset.balanceOf(user1);
        vm.prank(user1);
        underlyingAsset.approve(address(rVaultAsset2), 10 ether);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset2).mint(10 ether, user1);

        uint256 user1UnderlyingBalanceAfter = IERC20(address(underlyingAsset)).balanceOf(user1);

        assert(IERC20(rVaultAsset2).balanceOf(user1) == 10 ether);
        assert(user1UnderlyingBalanceAfter == user1UnderlyingBalanceBefore - 10 ether);
    }
}
