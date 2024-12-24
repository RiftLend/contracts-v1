import "./base.t.sol";

contract BorrowTest is Helpers{
    // function testBorrow() public {
    //     vm.selectFork(opMainnet);

    //     // history : deposit

    //     /////////////////////////////////////////////////////////////////////////////////////////////////////
    //     // set inputs and call action
    //     address caller = bob;
    //     address asset = address(Underlying);
    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = 800;
    //     uint256[] memory interestRateMode = new uint256[](1);
    //     interestRateMode[0] = 1;
    //     uint16 referralCode = 0;
    //     address onBehalfOf = bob;
    //     uint256 sendToChainId = block.chainid;
    //     uint256[] memory chainIds = new uint256[](1);
    //     chainIds[0] = block.chainid;
    //     /***************************************************************************************************/
    //     _borrow(caller, asset, amounts, interestRateMode, referralCode, onBehalfOf, sendToChainId, chainIds);
    //     /***************************************************************************************************/


    //     // assert
    //     address superchainAsset_ = proxyLp.getReserveData(address(Underlying)).superchainAssetAddress;
    //     address aToken_ = proxyLp.getReserveData(address(Underlying)).aTokenAddress;
    //     // 1. underlying
    //     assertEq(Underlying.balanceOf(superchainAsset_), 200);

    //     // 2. superchainAsset
    //     assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 200);

    //     // 3. aToken
    //     assertEq(AToken(aToken_).balanceOf(alice), 200);

    //     // 4. sDT

    //     // 5. vDT
    // }
}