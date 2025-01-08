// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import  "../Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {IRVaultAsset} from "../../src/interfaces/IRVaultAsset.sol";

contract RVaultAssetTest is Base {
    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;
    
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Deploys the contracts and sets up the test environment.
     */
    function setUp() public override {
        super.setUp();
        
        // Create test accounts
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Fund accounts with underlying token
        deal(address(underlyingAsset), user1, INITIAL_BALANCE);
        deal(address(underlyingAsset), user2, INITIAL_BALANCE);
        
        // Approve rVaultAsset to spend underlying tokens
        vm.startPrank(user1);
        IERC20(underlyingAsset).approve(rVaultAsset1, type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        IERC20(underlyingAsset).approve(rVaultAsset1, type(uint256).max);
        vm.stopPrank();
        
        // Setup chain cluster types
        vm.startPrank(superProxyAdmin);
        IRVaultAsset(rVaultAsset1).setChainClusterType(block.chainid, DataTypes.Chain_Cluster_Types.SUPER_CHAIN);
        IRVaultAsset(rVaultAsset1).setChainClusterType(43114, DataTypes.Chain_Cluster_Types.OTHER); // Avalanche chain
        vm.stopPrank();
    }

    /**
     * @dev Tests that depositing into the rVaultAsset increases the user's balance and reduces their underlying token balance.
     */
    function test_rVaultAssetDeposit() public {
        vm.startPrank(user1);
        uint256 beforeBalance = IERC20(underlyingAsset).balanceOf(user1);
        
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
        
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(underlyingAsset).balanceOf(user1), beforeBalance - DEPOSIT_AMOUNT);
        assertEq(IRVaultAsset(rVaultAsset1).totalBalances(), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @dev Tests that minting into the rVaultAsset increases the user's balance and reduces their underlying token balance.
     */
    function test_rVaultAssetMint() public {
        vm.startPrank(user1);
        uint256 beforeBalance = IERC20(underlyingAsset).balanceOf(user1);
        
        IRVaultAsset(rVaultAsset1).mint(DEPOSIT_AMOUNT, user1);
        
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(IERC20(underlyingAsset).balanceOf(user1), beforeBalance - DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @dev Tests that withdrawals from the rVaultAsset are only allowed after a cooldown period has passed.
     */
    function test_rVaultAssetWithdrawWithCooldown() public {
        // First deposit
        vm.startPrank(user1);
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
        
        // First withdrawal should work
        uint256 beforeBalance = IERC20(underlyingAsset).balanceOf(user1);
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);
        
        // Verify first withdrawal
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), DEPOSIT_AMOUNT / 2);
        assertEq(IERC20(underlyingAsset).balanceOf(user1), beforeBalance + DEPOSIT_AMOUNT / 2);
        
        // Immediate second withdrawal should fail
        vm.expectRevert("Withdrawal cooldown period not Passed");
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);
        
        // After cooldown period, withdrawal should succeed
        vm.warp(block.timestamp + IRVaultAsset(rVaultAsset1).WITHDRAW_COOL_DOWN_PERIOD() + 1);
        IRVaultAsset(rVaultAsset1).withdraw(DEPOSIT_AMOUNT / 2, user1, user1);
        
        // Verify final state
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), 0);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), 0);
        vm.stopPrank();
    }

    /**
     * @dev Tests that transfers and balance tracking work correctly.
     */
    function test_rVaultAssetTransferAndBalanceTracking() public {
        vm.startPrank(user1);
        IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
        
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
        vm.startPrank(superProxyAdmin);
        
        // Test withdrawal cooldown period modification
        uint256 newPeriod = 2 days;
        IRVaultAsset(rVaultAsset1).setWithdrawCoolDownPeriod(newPeriod);
        assertEq(IRVaultAsset(rVaultAsset1).WITHDRAW_COOL_DOWN_PERIOD(), newPeriod);
        
        // Test cluster type modification
        uint256 newChainId = 42161; // Arbitrum
        IRVaultAsset(rVaultAsset1).setChainClusterType(newChainId, DataTypes.Chain_Cluster_Types.OTHER);
        assertEq(uint256(IRVaultAsset(rVaultAsset1).chainIdToClusterType(newChainId)), uint256(DataTypes.Chain_Cluster_Types.OTHER));
        
        // Test intra-cluster service type toggle
        IRVaultAsset(rVaultAsset1).setIntraClusterServiceType(true);
        assertTrue(IRVaultAsset(rVaultAsset1).isSuperTokenBridgeEnabled());
        
        vm.stopPrank();
    }

    /**
     * @dev Tests that non-admins cannot modify the rVaultAsset's state.
     */
    function testFail_rVaultAssetNonAdminFunctions() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        IRVaultAsset(rVaultAsset1).setWithdrawCoolDownPeriod(2 days);
        
        vm.expectRevert();
        IRVaultAsset(rVaultAsset1).setChainClusterType(1, DataTypes.Chain_Cluster_Types.SUPER_CHAIN);
        
        vm.expectRevert();
        IRVaultAsset(rVaultAsset1).setIntraClusterServiceType(true);
        
        vm.stopPrank();
    }

    /**
     * @dev Tests that depositing with a fuzzed amount works correctly.
     */
    function test_rVaultAssetFuzzDeposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);
        
        deal(address(underlyingAsset), user1, amount);
        
        vm.startPrank(user1);
        IRVaultAsset(rVaultAsset1).deposit(amount, user1);
        
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), amount);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), amount);
        vm.stopPrank();
    }

    /**
     * @dev Tests that withdrawing with a fuzzed amount works correctly.
     */
    function test_rVaultAssetFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        
        deal(address(underlyingAsset), user1, depositAmount);
        
        vm.startPrank(user1);
        IRVaultAsset(rVaultAsset1).deposit(depositAmount, user1);
        
        vm.warp(block.timestamp + IRVaultAsset(rVaultAsset1).WITHDRAW_COOL_DOWN_PERIOD() + 1);
        IRVaultAsset(rVaultAsset1).withdraw(withdrawAmount, user1, user1);
        
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(IERC20(rVaultAsset1).balanceOf(user1), depositAmount - withdrawAmount);
        vm.stopPrank();
    }




    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Bridging Tests                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    // function test_rVaultAssetDistributeRVaultAsset() public {
    //     // Setup multiple holders
    //     vm.startPrank(user1);
    //     IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);
    //     vm.stopPrank();
        
    //     vm.startPrank(user2);
    //     IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user2);
    //     vm.stopPrank();

    //     // we Trigger distribution through a mock bridge operation here
    // }
    //     function test_rVaultAssetBridgingBetweenClusters() public {
    //     // Setup initial state
    //     vm.prank(user1);
    //     IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);

    //     // Bridge to Avalanche (cross-cluster)
    //     vm.prank(router);
    //     IRVaultAsset(rVaultAsset1).bridge(user2, 43114, DEPOSIT_AMOUNT);
    // }

    // function test_rVaultAssetIntraClusterBridging() public {
    //     // Enable intra-cluster bridging
    //     vm.prank(superProxyAdmin);
    //     IRVaultAsset(rVaultAsset1).setIntraClusterServiceType(true);
        
    //     vm.prank(user1);
    //     IRVaultAsset(rVaultAsset1).deposit(DEPOSIT_AMOUNT, user1);

    //     // Bridge within same cluster
    //     vm.prank(router);
    //     IRVaultAsset(rVaultAsset1).bridge(user2, block.chainid, DEPOSIT_AMOUNT);
    // }
}
