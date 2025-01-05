// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "../Base.t.sol";

contract LendingPoolTest is Base {
    // Test deposit of underlying tokens on superchain
    //  the Lending pool will take the underlying , wrap into rVaultAsset and then deposit into rToken
    function test_lp_Deposit() public {
        // ########### Prepare deposit params
        uint256[1] memory amounts;
        amounts[0] = 10 ether;
        address onBehalfOf = user1;
        uint16 referralCode = 0;
        uint256[1] memory chainIds;
        chainIds[0] = 1;

        (address rVaultAsset) = proxyLp.getRVaultAssetOrRevert(address(underlyingAsset));

        // ########### Approve rVault's underlying deposit params
        vm.prank(onBehalfOf);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);
        // check allowance given
        IERC20(underlyingAsset).allowance(onBehalfOf, address(proxyLp));

        // ########### Deposit through router ###########

        vm.prank(address(router));
        proxyLp.deposit(onBehalfOf, address(underlyingAsset), amounts[0], onBehalfOf, referralCode);

        address rToken = proxyLp.getReserveData(rVaultAsset).rTokenAddress;

        console.log(rVaultAsset);
        assertEq(IERC20(rVaultAsset).balanceOf(rToken), amounts[0]);
    }

    // TODO:test is the userconfig for the rVaultAsset correct?
    // TODO:test does the rVaultAsset have the correct underlying?
    // TODO:test does the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    // assertEq(underlyingAsset.balanceOf(onBehalfOf), 90 ether);
}
