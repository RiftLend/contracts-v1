// import "./Base.t.sol";

// contract RVaultAsset_Deposit  is RVaultAssetTest{

//      function test_rvaultAsset_Deposit() public {
//         uint256 depositAmount = 100 ether;

//         // Deposit underlying asset into RVaultAsset
//         vm.prank(owner);
//         rVaultAsset.deposit(depositAmount, owner);

//         // Check the balance of RVaultAsset and owner
//         assertEq(rVaultAsset.balanceOf(owner), depositAmount);
//         assertEq(underlyingAsset.balanceOf(address(rVaultAsset)), depositAmount);
//     }
// }
