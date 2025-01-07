// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "../Base.t.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {UserConfiguration} from "../../src/libraries/configuration/UserConfiguration.sol";

contract LendingPoolTest is Base {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /// @dev tests that the user can deposit underlying asset to the pool
    /// @dev tests that the user config is updated correctly
    /// @dev tests that the rToken has the correct balance
    function test_lpDeposit() public {
        // ########### Prepare deposit params
        uint256[1] memory amounts;
        amounts[0] = 10 ether;
        address onBehalfOf = user1;
        uint16 referralCode = 0;
        uint256[1] memory chainIds;
        chainIds[0] = 1;

        address rVaultAsset = proxyLp.getRVaultAssetOrRevert(address(underlyingAsset));

        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);
        //   router.deposit()
        // ########### Deposit through router ###########
        // // Start the recorder
        //       vm.recordLogs();

        //       // initiate deposit
        //       vm.prank(user1)
        //       router.deposit(underlyingAsset, amounts, onBehalfOf, referralCode, chainIds);
        //       // Relayer picks the emitted event
        //       Vm.Log[] memory entries = vm.getRecordedLogs();
        //       ( address _user,,uint256 _amount,address _onBehalfOf,uint16 _referral,,)=abi.decode(entries[0].data, (address,address,uint256,address,uint16,uint256,uint256))

        vm.prank(address(router));
        proxyLp.deposit(onBehalfOf, address(underlyingAsset), amounts[0], onBehalfOf, referralCode);
        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset).balanceOf(rToken), amounts[0]);

        // TODO:test is the userconfig for the rVaultAsset correct?
        DataTypes.UserConfigurationMap memory userConfig = proxyLp.getUserConfiguration(onBehalfOf);
        assert(userConfig.isUsingAsCollateralOrBorrowing(reserveData.id) == true);
    }

    /// @dev tests that the rVaultAsset has the correct underlying
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset1 the underlying is superasset
    function test_lpRVaultUnderlyingIsCorrect() public {
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset1).asset(), address(superAsset));
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset2).asset(), address(underlyingAsset));
    }

    // TODO:test does the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    /// @dev tests that the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset2 the underlying is superasset
    function test_lpRVaultMintBurnCorrectly() public {
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

        uint256 user1UnderlyingBalanceBefore = IERC20(underlyingAsset).balanceOf(user1);
        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(rVaultAsset2), 10 ether);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset2).mint(10 ether, user1);

        uint256 user1UnderlyingBalanceAfter = IERC20(address(underlyingAsset)).balanceOf(user1);

        assert(IERC20(rVaultAsset2).balanceOf(user1) == 10 ether);
        assert(user1UnderlyingBalanceAfter == user1UnderlyingBalanceBefore - 10 ether);
    }
}
