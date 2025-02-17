// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import "../Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {IRVaultAsset} from "../../src/interfaces/IRVaultAsset.sol";

contract RVaultAssetTestBase is Base {
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
        address rVaultAssetUnderlying = IRVaultAsset(rVaultAsset1).asset();

        deal(address(underlyingAsset), user1, INITIAL_BALANCE);
        deal(address(underlyingAsset), user2, INITIAL_BALANCE);
        // Approve rVaultAsset to spend underlying tokens
        vm.startPrank(user1);
        IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
        IERC20(rVaultAssetUnderlying).approve(rVaultAsset1, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
        IERC20(rVaultAssetUnderlying).approve(rVaultAsset1, type(uint256).max);
        vm.stopPrank();

        // Get superAssets
        if (IRVaultAsset(rVaultAsset1).pool_type() == 1) {
            vm.prank(user1);
            superAsset.deposit(user1, DEPOSIT_AMOUNT);
            vm.prank(user2);
            superAsset.deposit(user2, DEPOSIT_AMOUNT);
        }
    }
}
