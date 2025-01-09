// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import "../Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {IRVaultAsset} from "../../src/interfaces/IRVaultAsset.sol";

contract RVaultAssetTest is Base {
    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

   

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
