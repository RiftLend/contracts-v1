

import "./Base.t.sol";


contract RVaultAsset_WithdrawTest is RVaultAssetTest  {

    function testWithdraw() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        // Deposit underlying asset into RVaultAsset
        vm.prank(owner);
        rVaultAsset.deposit(depositAmount, owner);

        // Withdraw underlying asset from RVaultAsset
        vm.prank(owner);
        rVaultAsset.withdraw(withdrawAmount, receiver, owner);

        // Check the balance of RVaultAsset, owner, and receiver
        assertEq(rVaultAsset.balanceOf(owner), depositAmount - withdrawAmount);
        assertEq(underlyingAsset.balanceOf(address(rVaultAsset)), depositAmount - withdrawAmount);
        assertEq(underlyingAsset.balanceOf(receiver), withdrawAmount);
    }    
}