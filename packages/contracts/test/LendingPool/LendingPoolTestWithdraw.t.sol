// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestDeposit.t.sol";

contract LendingPoolTestWithdraw is LendingPoolTestDeposit {
    function test_lpWithdraw() public {
        test_lpDeposit();
        (uint256[] memory amounts, address onBehalfOf,, uint256[] memory chainIds) = getActionXConfig();

        // ########### Withdraw through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.withdraw(address(underlyingAsset), amounts, onBehalfOf, block.chainid, chainIds);

        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );
        // event CrossChainWithdraw( uint256 fromChainId, address sender, address asset, uint256 amount, address to, uint256 toChainId);
        (uint256 _fromChainId, address _sender, address _asset, uint256 _amount, address _to, uint256 _toChainId) =
            abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint256));
        bytes32 _selector = CrossChainWithdraw.selector;

        _eventData[0] = abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _to, _toChainId);

        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);
    }
}
