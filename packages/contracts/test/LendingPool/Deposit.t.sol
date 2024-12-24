import "./base.t.sol";

contract DepositTest is Helpers{
        function testDeposit() public {
        vm.selectFork(chainId[0]);
        temps storage t = config[chainId[0]];

        /////////////////////////////////////////////////////////////////////
        // set inputs and call action
        address caller = t.alice;
        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = t.alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        /*******************************************************************/
        _deposit(chainId[0], caller, asset, amounts, onBehalfOf, referralCode, chainIds);
        /*******************************************************************/

        // assert
        address superchainAsset_ = proxyLp.getReserveData(address(Underlying)).superchainAssetAddress;
        address aToken_ = proxyLp.getReserveData(address(Underlying)).aTokenAddress;
        // 1. underlying
        assertEq(Underlying.balanceOf(superchainAsset_), 1000);

        // 2. superchainAsset
        assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 1000);

        // 3. aToken
        assertEq(AToken(aToken_).balanceOf(t.alice), 1000);
    }
}