// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBase.t.sol";

contract LendingPoolTestDeposit is LendingPoolTestBase {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    function test_lpDeposit() public {
        super.setUp();
        // ########### Prepare deposit params
        (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds) =
            getActionXConfig();

        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);

        // ########### Deposit through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.deposit(address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds);
        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );

        (
            uint256 _fromChainId,
            address _sender,
            address _asset,
            uint256 _amount,
            address _onBehalfOf,
            uint16 _referralCode
        ) = abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint16));
        bytes32 _selector = CrossChainDeposit.selector;

        _eventData[0] =
            abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, _referralCode);

        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);

        DataTypes.UserConfigurationMap memory userConfig = proxyLp.getUserConfiguration(onBehalfOf);
        assert(userConfig.isUsingAsCollateralOrBorrowing(reserveData.id) == true);
    }

    function getActionXConfig()
        public
        view
        returns (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds)
    {
        amounts = new uint256[](1);
        amounts[0] = 10 ether;
        onBehalfOf = user1;
        referralCode = 0;
        chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
    }
}
