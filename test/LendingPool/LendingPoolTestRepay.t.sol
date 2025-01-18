// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBorrow.t.sol";
import {CrossChainRepay, CrossChainRepayFinalize, Repay} from "src/interfaces/ILendingPool.sol";
import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";

contract LendingPoolTestRepay is LendingPoolTestBorrow {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_lpRepay() external {
        super.setUp();
        test_lpBorrow();
        (uint256[] memory amounts, address onBehalfOf,, uint256[] memory chainIds) = getActionXConfig();

        // Adjust Repay amounts
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = amounts[i] / 2; //only borrowed 50% of the amount deposited
        }

        address asset = address(underlyingAsset);
        vm.prank(user1);
        IERC20(asset).approve(address(router), type(uint256).max);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Repay Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.chainId(supportedChains[0].chainId);
        DataTypes.RepayParam[] memory _repayParams;
        _repayParams = new DataTypes.RepayParam[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            _repayParams[i] = DataTypes.RepayParam(block.chainid, chainIds[i], amounts[i]);
        }

        vm.recordLogs();
        vm.prank(user1);
        router.repay(asset, onBehalfOf, _repayParams);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Repay Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Processing Cross-Chain Repay Event ");

        Identifier[] memory _identifier = new Identifier[](entries.length);
        bytes[] memory _eventData = new bytes[](entries.length);
        uint256[] memory _logindex = new uint256[](entries.length);
        address originAddress = address(0x4200000000000000000000000000000000000023);

        uint256 amount;
        address sender;
        bytes32 _selector = CrossChainRepay.selector;
        bytes memory eventData;
        uint256 fundChainId;
        uint256 debtChainId;

        for (uint256 index = 0; index < entries.length; index++) {
            eventData = entries[index].data;
            _identifier[index] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
            _logindex[index] = 0;

            (fundChainId, sender, asset, amount, onBehalfOf, debtChainId) =
                abi.decode(eventData, (uint256, address, address, uint256, address, uint256));

            _eventData[index] = abi.encode(_selector, fundChainId, sender, asset, amount, onBehalfOf, debtChainId);
        }
        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and get CrossChainRepayFinalize event     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        ////////////////////

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and perform Actual repay on debtChain     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        console.log("Dispatch and perform Actual repay on debtChain ");

        entries = vm.getRecordedLogs();
        bytes[] memory events = EventUtils.findEventsBySelector(entries, CrossChainRepayFinalize.selector);

        uint256[] memory debtChains = new uint256[](events.length);

        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];
            (debtChainId, sender, onBehalfOf, amount, asset) =
                abi.decode(eventData, (uint256, address, address, uint256, address));

            _eventData[index] =
                abi.encode(CrossChainRepayFinalize.selector, debtChainId, sender, onBehalfOf, amount, asset);
            debtChains[index] = debtChainId;
        }

        vm.recordLogs();
        for (uint256 index = 0; index < debtChains.length; index++) {
            vm.chainId(debtChains[index]);
            vm.prank(relayer);
            router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        console.log("Cross-Chain State Sync : Repay");
        uint256 srcChain = block.chainid;
        entries = vm.getRecordedLogs();
        events = EventUtils.findEventsBySelector(entries, Repay.selector);

        address repayer;
        uint256 mode;
        uint256 amountBurned;

        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];

            (asset, amount, sender, repayer, mode, amountBurned) =
                abi.decode(eventData, (address, uint256, address, address, uint256, uint256));
            _eventData[index] = abi.encode(Repay.selector, asset, amount, sender, repayer, mode, amountBurned);
        }

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i].chainId != srcChain) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
                assert(
                    VariableDebtToken(address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress))
                        .crossChainUserBalance(user1) == 0
                );
            }
        }
    }
}
