// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestDeposit.t.sol";
import {IOFT} from "../../src/libraries/helpers/layerzero/IOFT.sol";
import {Vm} from "forge-std/Vm.sol";
import {OFTLogic} from "../../src/libraries/logic/OFTLogic.sol";
import {Origin, ILayerZeroEndpointV2} from "../../src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {Packet} from "../../src/libraries/helpers/layerzero/ISendLib.sol";
import {ILayerZeroEndpointV2} from "../../src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";

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
        console.log("withdraw success");
        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;
        address originAddress = address(0x4200000000000000000000000000000000000023);

        _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
        // event CrossChainWithdraw( uint256 fromChainId, address sender, address asset, uint256 amount, address to, uint256 toChainId);
        (uint256 _fromChainId, address _sender, address _asset, uint256 _amount, address _to, uint256 _toChainId) =
            abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint256));
        bytes32 _selector = CrossChainWithdraw.selector;

        _eventData[0] = abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _to, _toChainId);

        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        // On the destination chain , the executor picks up the emitted logs ,
        // decodes the packet  and initiate a call to lzReceive on destination address on destination chain

        // Getting the emitted logs of interest out of all
        entries = vm.getRecordedLogs();
        bytes memory oftSentLogData = findEventBySelector(entries, IOFT.OFTSent.selector);

        // event OFTSent(bytes32  guid,uint32 dstEid,address  fromAddress,uint256 amountSentLD,uint256 amountReceivedLD);
        (bytes32 guid, uint32 dstEid,,, uint256 amountReceivedLD) =
            abi.decode(oftSentLogData, (bytes32, uint32, address, uint256, uint256));
        console.log("decoded oftsent");

        // Building a packet from logs and passing it to lzReceive
        Origin memory _origin = Origin(uint32(_fromChainId), bytes32(uint256(uint160(address(lzEndpoint)))), 1);
        vm.chainId(dstEid);
        // funds are credited to rVaultAsset1 by bridge logic
        deal(address(superAsset), rVaultAsset1, amountReceivedLD);
        vm.startPrank(address(lzEndpoint));
        IRVaultAsset(rVaultAsset1).lzReceive(
            _origin, guid, abi.encode(onBehalfOf, amountReceivedLD), address(lzEndpoint), bytes("")
        );
        vm.stopPrank();

        // DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        // address rToken = reserveData.rTokenAddress;

        // assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);
    }

    function findEventBySelector(Vm.Log[] memory entries, bytes32 _selector) public pure returns (bytes memory) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == _selector) {
                return entries[i].data;
            }
        }
        return bytes("");
    }
}
