// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBorrow.t.sol";
import {CrossChainLiquidationCall} from "src/interfaces/ILendingPool.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";
import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";

contract LendingPoolTestLiquidation is LendingPoolTestBorrow {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_lpLiquidation() external {
        uint256 amount;
        address sender;
        bytes memory eventData;
        uint256 chainId;
        uint256 _debtToCover;
        address collateralAsset;
        address debtAsset;
        address user;
        bool receiveRToken = false;
        address onBehalfOf;
        Identifier[] memory _identifier;
        bytes[] memory _eventData;
        uint256[] memory _logindex;
        uint256[] memory amounts;
        uint256[] memory chainIds;
        uint256[] memory debtToCover;
        Vm.Log[] memory entries;
        bytes[] memory events;
        uint256 liquidatedCollateralAmount;
        address _liquidator;
        uint256 variableDebtBurned;
        uint256 collateralRTokenBurned;

        address originAddress = address(0x4200000000000000000000000000000000000023);

        bytes32 _selector;

        super.setUp();

        (amounts, onBehalfOf,, chainIds) = getActionXConfig();
        // Adjust Borrow amounts
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = (amounts[i] * 80) / 100; // borrow 81% of the amount deposited so that it is subject to liquidation
        }
        _borrow(amounts);

        address oracle =(lpAddressProvider1.getPriceOracle());
        uint256 price=MockPriceOracle(oracle).getAssetPrice(address(underlyingAsset));
        vm.prank(owner);
        MockPriceOracle(oracle).setPrice( price/2);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Liquidation Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        collateralAsset = address(underlyingAsset);
        debtAsset = address(underlyingAsset);
        user = onBehalfOf;

        debtToCover = new uint256[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            debtToCover[i] = amounts[i];
        }
        vm.chainId(supportedChains[0].chainId);
        vm.recordLogs();
        vm.prank(liquidator);
        IERC20(debtAsset).approve(address(proxyLp), type(uint256).max);

        vm.prank(liquidator);
        router.liquidationCall(collateralAsset, debtAsset, user, debtToCover, chainIds, receiveRToken);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Liquidation Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Processing Cross-Chain Liquidation Event ");

        entries = vm.getRecordedLogs();

        _selector = CrossChainLiquidationCall.selector;
        events = EventUtils.findEventsBySelector(entries, _selector);

        _identifier = new Identifier[](events.length);
        _eventData = new bytes[](events.length);
        _logindex = new uint256[](events.length);

        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];
            _identifier[index] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
            _logindex[index] = 0;
            (chainId, sender, collateralAsset, debtAsset, user, _debtToCover, receiveRToken) =
                abi.decode(eventData, (uint256, address, address, address, address, uint256, bool));
            _eventData[index] =
                abi.encode(_selector, chainId, sender, collateralAsset, debtAsset, user, _debtToCover, receiveRToken);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and perform actual Liquidation using relayer     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Dispatch and perform actual Liquidation using relayer ");
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*     Assert Cross-Chain  Variable Debt Token  Token Balance */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Assert Cross-Chain  Variable Debt Token  Token Balance ");
        assert(
            VariableDebtToken(address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress))
                .crossChainUserBalance(user1) == 0
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Cross-Chain State Sync ");
        entries = vm.getRecordedLogs();
        _selector = ILendingPoolCollateralManager.LiquidationCall.selector;
        events = EventUtils.findEventsBySelector(entries, _selector);

        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];
            (
                collateralAsset,
                debtAsset,
                user,
                _debtToCover,
                liquidatedCollateralAmount,
                _liquidator,
                receiveRToken,
                variableDebtBurned,
                collateralRTokenBurned
            ) = abi.decode(eventData, (address, address, address, uint256, uint256, address, bool, uint256, uint256));
            _eventData[0] = abi.encode(
                _selector,
                collateralAsset,
                debtAsset,
                user,
                _debtToCover,
                liquidatedCollateralAmount,
                _liquidator,
                receiveRToken,
                variableDebtBurned,
                collateralRTokenBurned
            );
        }

        console.log("sync state of borrow for updating crosschain balances");
        uint256 srcChain = block.chainid;

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i].chainId != srcChain) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
            }
        }
    }
}
