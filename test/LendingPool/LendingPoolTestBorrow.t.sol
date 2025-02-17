// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       Imports                                 */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

import "./LendingPoolTestDeposit.t.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    Contract Definition                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract LendingPoolTestBorrow is LendingPoolTestDeposit {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Functions                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    uint256[] amounts;
    address onBehalfOf;
    uint16 referralCode;
    uint256[] chainIds;
    uint256 sendToChainId;
    address asset;
    address originAddress = address(0x4200000000000000000000000000000000000023);
    bytes eventData;
    DataTypes.BorrowEventParams borrowEventParams;
    DataTypes.CrosschainBorrowData crossChainBorrowData;
    bytes32 selector;

    function test_lpBorrow() public {
        super.setUp();
        uint256[] memory _amounts = new uint256[](0);
        _borrow(_amounts);
    }

    function _borrow(uint256[] memory _amounts) internal {
        Vm.Log[] memory entries;
        Identifier[] memory _identifier;
        bytes[] memory _eventData;
        uint256[] memory _logindex;

        test_lpDeposit();
        (amounts, onBehalfOf, referralCode, chainIds) = getActionXConfig();
        if (_amounts.length > 0) {
            amounts = _amounts;
        } else {
            // Adjust borrow amounts
            for (uint256 i = 0; i < amounts.length; i++) {
                amounts[i] = amounts[i] / 2; //only borrow 50% of the amount deposited
            }
        }

        sendToChainId = supportedChains[0].chainId;
        asset = address(underlyingAsset);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain Borrow Setup                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.chainId(supportedChains[0].chainId);
        vm.recordLogs();
        vm.prank(onBehalfOf);
        router.borrow(asset, amounts, referralCode, onBehalfOf, sendToChainId, chainIds);
        entries = vm.getRecordedLogs();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Borrow Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        _identifier = new Identifier[](entries.length);
        _eventData = new bytes[](entries.length);
        _logindex = new uint256[](entries.length);

        eventData = entries[0].data;
        _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
        _logindex[0] = 0;

        (crossChainBorrowData) = abi.decode(eventData, (DataTypes.CrosschainBorrowData));

        selector = ILendingPool.CrossChainBorrow.selector;
        _eventData[0] = abi.encode(
            selector,
            crossChainBorrowData.borrowFromChainId,
            crossChainBorrowData.sendToChainId,
            crossChainBorrowData.sender,
            crossChainBorrowData.asset,
            crossChainBorrowData.amount,
            crossChainBorrowData.onBehalfOf,
            crossChainBorrowData.referralCode
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
                .crossChainUserBalance(user1) == crossChainBorrowData.amount
        );

        entries = vm.getRecordedLogs();

        eventData = EventUtils.findEventsBySelector(entries, ILendingPool.Borrow.selector)[0];

        (borrowEventParams) = abi.decode(eventData, (DataTypes.BorrowEventParams));

        _eventData[0] = abi.encode(
            ILendingPool.Borrow.selector,
            borrowEventParams.reserve,
            borrowEventParams.amount,
            borrowEventParams.user,
            borrowEventParams.onBehalfOf,
            borrowEventParams.sendToChainId,
            borrowEventParams.borrowRate,
            borrowEventParams.mintMode,
            borrowEventParams.amountScaled,
            borrowEventParams.referral
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        console.log("sync state of borrow for updating crosschain balances");
        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i].chainId != block.chainid) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
            }
        }
    }
}
