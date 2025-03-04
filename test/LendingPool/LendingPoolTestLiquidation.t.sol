// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBorrow.t.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";
import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";

contract LendingPoolTestLiquidation is LendingPoolTestBorrow {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    bytes32 _selector;
    address user;
    address collateralAsset;
    address debtAsset;
    bool receiveRToken = true;
    DataTypes.LiquidationCallEventParams liquidationCallEventParams;
    DataTypes.CrosschainLiquidationCallData crossChainLiquidationCallData;
    address collateralRVaultAsset;
    address oracle;
    uint256 price;
    uint256 user1_vdebt_balance_before_liquidation;
    uint256 liquidator_rToken_balance_before_liquidation;
    uint256 user1_vdebt_balance_after_liquidation;
    uint256 liquidator_rToken_balance_after_liquidation;
    uint256[] debtToCover;
    bytes[] events;

    function test_lpLiquidation() external {
        Identifier[] memory _identifier;
        bytes[] memory _eventData;
        uint256[] memory _logindex;
        Vm.Log[] memory entries;

        super.setUp();

        (amounts, user,, chainIds) = getActionXConfig();
        // Adjust Borrow amounts
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = (amounts[i] * 70) / 100; // borrow 70% of the deposited amount only
        }
        _borrow(amounts);

        user1_vdebt_balance_before_liquidation = VariableDebtToken(
            address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress)
        ).crossChainUserBalance(user1);
        liquidator_rToken_balance_before_liquidation = RToken(
            payable(proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress)
        ).crossChainUserBalance(liquidator);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Liquidation Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        collateralAsset = address(underlyingAsset);
        debtAsset = address(underlyingAsset);

        // Stimulating Oracle price updates for collateral
        // Oracle keepers update the price to half of what it used to be
        oracle = (lpAddressProvider1.getPriceOracle());
        price = MockPriceOracle(oracle).getAssetPrice(collateralAsset);
        collateralRVaultAsset = proxyLp.getRVaultAssetOrRevert(collateralAsset);

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

        _selector = ILendingPool.CrossChainLiquidationCall.selector;
        events = EventUtils.findEventsBySelector(entries, _selector);

        _identifier = new Identifier[](events.length);
        _eventData = new bytes[](events.length);
        _logindex = new uint256[](events.length);

        for (uint256 index = 0; index < events.length; index++) {
            _identifier[index] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
            _logindex[index] = 0;
            (crossChainLiquidationCallData) = abi.decode(events[index], (DataTypes.CrosschainLiquidationCallData));
            _eventData[index] = abi.encode(
                _selector,
                crossChainLiquidationCallData.chainId,
                crossChainLiquidationCallData.sender,
                crossChainLiquidationCallData.collateralAsset,
                crossChainLiquidationCallData.debtAsset,
                crossChainLiquidationCallData.user,
                crossChainLiquidationCallData.debtToCover,
                crossChainLiquidationCallData.receiveRToken
            );
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and perform actual Liquidation using relayer     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Dispatch and perform actual Liquidation using relayer ");
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Cross-Chain State Sync ");
        entries = vm.getRecordedLogs();
        _selector = ILendingPoolCollateralManager.LiquidationCall.selector;
        events = EventUtils.findEventsBySelector(entries, _selector);

        for (uint256 index = 0; index < events.length; index++) {
            (liquidationCallEventParams) = abi.decode(events[index], (DataTypes.LiquidationCallEventParams));
            _eventData[index] = abi.encode(
                _selector,
                liquidationCallEventParams.collateralAsset,
                liquidationCallEventParams.debtAsset,
                liquidationCallEventParams.user,
                liquidationCallEventParams.debtToCover,
                liquidationCallEventParams.liquidatedCollateralAmount,
                liquidationCallEventParams.liquidator,
                liquidationCallEventParams.receiveRToken,
                liquidationCallEventParams.variableDebtBurned,
                liquidationCallEventParams.collateralRTokenBurned,
                liquidationCallEventParams.liquidatorSentScaled
            );
        }

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i].chainId != block.chainid) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
            }
        }
        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:°•.°+.*•´°•.°+.*•´*/
        /*     Assert Cross-Chain  Variable Debt Token  Balance is decreased for user1 **/
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.°•.°+.*•´°•.°+.*•´•*/
        console.log("Assert Cross-Chain  Variable Debt Token  Token Balance ");
        user1_vdebt_balance_after_liquidation = VariableDebtToken(
            address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress)
        ).crossChainUserBalance(user1);
        liquidator_rToken_balance_after_liquidation = RToken(
            payable(proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress)
        ).crossChainUserBalance(liquidator);

        assert(user1_vdebt_balance_before_liquidation > user1_vdebt_balance_after_liquidation);
        assert(liquidator_rToken_balance_after_liquidation > liquidator_rToken_balance_before_liquidation);
    }
}
