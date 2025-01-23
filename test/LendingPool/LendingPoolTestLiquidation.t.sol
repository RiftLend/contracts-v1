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
            amounts[i] = (amounts[i] * 70) / 100; // borrow 70% of the deposited amount only
        }
        _borrow(amounts);

        uint256 user1_vdebt_balance_before_liquidation = VariableDebtToken(
            address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress)
        ).crossChainUserBalance(user1);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Liquidation Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        collateralAsset = address(underlyingAsset);
        debtAsset = address(underlyingAsset);
        user = onBehalfOf;

        // Stimulating Oracle price updates for collateral
        // Oracle keepers update the price to half of what it used to be
        address oracle = (lpAddressProvider1.getPriceOracle());
        uint256 price = MockPriceOracle(oracle).getAssetPrice(address(collateralAsset));
        address collateralRVaultAsset = proxyLp.getRVaultAssetOrRevert(collateralAsset);

        vm.prank(owner);
        MockPriceOracle(oracle).setPrice(collateralAsset, price / 2);
        vm.prank(owner);
        MockPriceOracle(oracle).setPrice(collateralRVaultAsset, price / 2);

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

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:°•.°+.*•´°•.°+.*•´*/
        /*     Assert Cross-Chain  Variable Debt Token  Balance is decreased for user1 **/
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.°•.°+.*•´°•.°+.*•´•*/
        console.log("Assert Cross-Chain  Variable Debt Token  Token Balance ");
        uint256 user1_vdebt_balance_after_liquidation = VariableDebtToken(
            address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress)
        ).crossChainUserBalance(user1);

        assert(user1_vdebt_balance_before_liquidation > user1_vdebt_balance_after_liquidation);

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
            _eventData[index] = abi.encode(
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
