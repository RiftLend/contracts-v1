// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBorrow.t.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";

contract LendingPoolTestRepay is LendingPoolTestBorrow {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_lpRepay() external {
        super.setUp();

        uint256[] memory amounts;
        uint256[] memory chainIds;
        Identifier[] memory _identifier;
        bytes[] memory _eventData;
        uint256[] memory _logindex;
        bytes[] memory events;
        Vm.Log[] memory entries;
        uint256[] memory debtChains;
        bytes32 _selector;
        address onBehalfOf;
        address originAddress = address(0x4200000000000000000000000000000000000023);

        _borrow(amounts);
        (amounts, onBehalfOf,, chainIds) = getActionXConfig();

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

        entries = vm.getRecordedLogs();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Repay Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Processing Cross-Chain Repay Event ");

        _identifier = new Identifier[](entries.length);
        _eventData = new bytes[](entries.length);
        _logindex = new uint256[](entries.length);
        _selector = ILendingPool.CrossChainRepay.selector;

        for (uint256 index = 0; index < entries.length; index++) {
            _identifier[index] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
            _logindex[index] = 0;

            (DataTypes.CrosschainRepayData memory crossChainRepayData) = abi.decode(entries[index].data, (DataTypes.CrosschainRepayData));

            _eventData[index] = abi.encode(
                _selector,
                crossChainRepayData.fundChainId,
                crossChainRepayData.sender,
                crossChainRepayData.asset,
                crossChainRepayData.amount,
                crossChainRepayData.onBehalfOf,
                crossChainRepayData.debtChainId
            );
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
        events = EventUtils.findEventsBySelector(entries, ILendingPool.CrossChainRepayFinalize.selector);

        debtChains = new uint256[](events.length);

        for (uint256 index = 0; index < events.length; index++) {
            (DataTypes.CrosschainRepayFinalizeData memory crossChainRepayFinalizeData) =
                abi.decode( events[index], (DataTypes.CrosschainRepayFinalizeData));

            _eventData[index] = abi.encode(
                ILendingPool.CrossChainRepayFinalize.selector,
                crossChainRepayFinalizeData.debtChainId,
                crossChainRepayFinalizeData.sender,
                crossChainRepayFinalizeData.onBehalfOf,
                crossChainRepayFinalizeData.amount,
                crossChainRepayFinalizeData.asset
            );
            debtChains[index] = crossChainRepayFinalizeData.debtChainId;
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
        events = EventUtils.findEventsBySelector(entries, ILendingPool.Repay.selector);

        for (uint256 index = 0; index < events.length; index++) {

            (DataTypes.RepayEventParams memory repayEventParams) = abi.decode(events[index], (DataTypes.RepayEventParams));
            _eventData[index] = abi.encode(
                ILendingPool.Repay.selector,
                repayEventParams.asset,
                repayEventParams.amount,
                repayEventParams.sender,
                repayEventParams.repayer,
                repayEventParams.mode,
                repayEventParams.amountBurned
            );
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
