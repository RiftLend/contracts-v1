// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       Imports                                 */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

import "./LendingPoolTestDeposit.t.sol";
import {CrossChainBorrow, Borrow} from "src/interfaces/ILendingPool.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    Contract Definition                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract LendingPoolTestBorrow is LendingPoolTestDeposit {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_lpBorrow() public {
        super.setUp();
        test_lpDeposit();
        (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds) =
            getActionXConfig();

        // Adjust borrow amounts
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = amounts[i] / 2; //only borrow 50% of the amount deposited
        }
        uint256 sendToChainId = supportedChains[0].chainId;
        address asset = address(underlyingAsset);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Borrow Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.chainId(supportedChains[0].chainId);
        vm.recordLogs();
        vm.prank(onBehalfOf);
        router.borrow(asset, amounts, referralCode, onBehalfOf, sendToChainId, chainIds);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Borrow Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        Identifier[] memory _identifier = new Identifier[](entries.length);
        bytes[] memory _eventData = new bytes[](entries.length);
        uint256[] memory _logindex = new uint256[](entries.length);
        address originAddress = address(0x4200000000000000000000000000000000000023);

        uint256 amount;
        address sender;
        uint256 borrowFromChainId;

        bytes memory eventData = entries[0].data;
        _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
        _logindex[0] = 0;

        (borrowFromChainId, sendToChainId, sender, asset, amount, onBehalfOf, referralCode) =
            abi.decode(eventData, (uint256, uint256, address, address, uint256, address, uint16));

        bytes32 _selector = CrossChainBorrow.selector;
        _eventData[0] = abi.encode(
            _selector, borrowFromChainId, bytes32(0), sendToChainId, sender, asset, amount, onBehalfOf, referralCode
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and perform actual Borrow using relayer     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*     Assert Cross-Chain  Variable Debt Token  Token Balance */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        assert(
            VariableDebtToken(address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress))
                .crossChainUserBalance(user1) == amount
        );

        entries = vm.getRecordedLogs();

        uint256 borrowRate;
        uint256 mintMode;
        uint256 amountScaled;
        address reserve;

        eventData = EventUtils.findEventsBySelector(entries, Borrow.selector)[0];

        (reserve, amount, sender, onBehalfOf, sendToChainId, borrowRate, mintMode, amountScaled, referralCode) =
            abi.decode(eventData, (address, uint256, address, address, uint256, uint256, uint256, uint256, uint16));

        _eventData[0] = abi.encode(
            Borrow.selector,
            reserve,
            amount,
            sender,
            onBehalfOf,
            sendToChainId,
            borrowRate,
            mintMode,
            amountScaled,
            referralCode
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
