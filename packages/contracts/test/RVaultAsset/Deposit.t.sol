pragma solidity 0.8.25;
// import './Base.t.sol';

// contract RVaultAsset_Deposit is Base {

//   function test_rvaultAsset_Deposit(uint256 assets) public {
//     uint256 depositAmount = 100 ether;

//     // Deposit underlying asset into RVaultAsset
//     vm.prank(owner);
//     IRVaultAsset(rVaultAsset).deposit(depositAmount, owner);

//     // Check the balance of RVaultAsset and owner
//     assertEq(IERC20(rVaultAsset).balanceOf(owner), depositAmount);
//     assertEq(underlyingAsset.balanceOf(rVaultAsset), depositAmount);
//   }

//   function test_rvaultAsset_deposit_success(uint256 assets,address receiver) public {
//     // Arrange
//     vm.prank(user1);
//     IERC20(IRVaultAsset(rVaultAsset).underlying()).approve(
//       rVaultAsset,
//       assets
//     );

//     // Act
//     uint256 shares = IRVaultAsset(rVaultAsset).deposit(assets, receiver);

//     // Assert
//     assertEq(shares, assets);
//     assertEq(IRVaultAsset(rVaultAsset).totalBalances(), assets);
//     assertEq(IERC20(rVaultAsset).balances(receiver), assets);
//     assertEq(IRVaultAsset(rVaultAsset).isRVaultAssetHolder(receiver), true);
//     assertEq(IRVaultAsset(rVaultAsset).rVaultAssetHolder(0), receiver);
//   }

//   function test_rvaultAsset_deposit_zero_assets(uint256 assets,address receiver) public {
//     // Arrange
//     vm.prank(user1);
//     IERC20(IRVaultAsset(rVaultAsset).underlying()).approve(rVaultAsset, 0);

//     // Act and Assert
//     vm.expectRevert('ERC20: insufficient allowance');
//     IRVaultAsset(rVaultAsset).deposit(0, receiver);
//   }

//   function test_rvaultAsset_deposit_insufficient_allowance(uint256 assets,address receiver)public {
//     // Arrange
//     vm.prank(user1);
//     IERC20(IRVaultAsset(rVaultAsset).underlying()).approve(
//       rVaultAsset,
//       assets - 1
//     );

//     // Act and Assert
//     vm.expectRevert('ERC20: insufficient allowance');
//     IRVaultAsset(rVaultAsset).deposit(assets, receiver);
//   }

//   function test_rvaultAsset_deposit_receiver_already_holder(uint256 assets,address receiver) public {
//     // Arrange
//     vm.prank(user1);
//     IERC20(IRVaultAsset(rVaultAsset).underlying()).approve(
//       rVaultAsset,
//       assets
//     );
//     IRVaultAsset(rVaultAsset).deposit(assets, receiver);

//     // Act
//     uint256 shares = IRVaultAsset(rVaultAsset).deposit(assets, receiver);

//     // Assert
//     assertEq(shares, assets);
//     assertEq(IRVaultAsset(rVaultAsset).totalBalances(), assets * 2);
//     assertEq(IERC20(rVaultAsset).balances(receiver), assets * 2);
//     assertEq(IRVaultAsset(rVaultAsset).isRVaultAssetHolder(receiver), true);
//     assertEq(IRVaultAsset(rVaultAsset).rVaultAssetHolder(0), receiver);
//   }

//   function test_rvaultAsset_deposit_receiver_not_holder(uint256 assets,address receiver) public {
//     // Arrange
//     vm.prank(user1);
//     IERC20(IRVaultAsset(rVaultAsset).underlying()).approve(
//       rVaultAsset,
//       assets
//     );

//     // Act
//     uint256 shares = IRVaultAsset(rVaultAsset).deposit(assets, address(3));

//     // Assert
//     assertEq(shares, assets);
//     assertEq(IRVaultAsset(rVaultAsset).totalBalances(), assets);
//     assertEq(IERC20(rVaultAsset).balances(address(3)), assets);
//     assertEq(IRVaultAsset(rVaultAsset).isRVaultAssetHolder(address(3)), true);
//     assertEq(IRVaultAsset(rVaultAsset).rVaultAssetHolder(0), address(3));
//   }

// }
