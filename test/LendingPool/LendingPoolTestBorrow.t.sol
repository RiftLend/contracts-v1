// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestDeposit.t.sol";

contract LendingPoolTestBorrow is LendingPoolTestDeposit {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    function test_lpBorrow() public {
        super.setUp();
        test_lpDeposit();
        (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds) =
            getActionXConfig();

        uint256 sendToChainId = supportedChains[1].chainId;

        address asset = address(underlyingAsset);
        // Start the recorder
        vm.recordLogs();
        router.borrow(asset, amounts, referralCode, onBehalfOf, sendToChainId, chainIds);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        Identifier[] memory _identifier = new Identifier[](entries.length);
        bytes[] memory _eventData = new bytes[](entries.length);
        uint256[] memory _logindex = new uint256[](entries.length);
        address originAddress = address(0x4200000000000000000000000000000000000023);

        uint256 amount;
        address sender;
        uint256 borrowFromChainId;

        for (uint256 i = 0; i < entries.length; i++) {
            bytes memory eventData = entries[i].data;
            _identifier[i] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
            _logindex[i] = 0;

            (borrowFromChainId, sendToChainId, sender, asset, amount, onBehalfOf, referralCode) =
                abi.decode(eventData, (uint256, uint256, address, address, uint256, address, uint16));
            bytes32 _selector = CrossChainDeposit.selector;
            _eventData[i] =
                abi.encode(_selector, borrowFromChainId, sendToChainId, sender, asset, amount, onBehalfOf, referralCode);
        }
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
        entries = vm.getRecordedLogs();

        console.log("sync state of borrow for updating crosschain balances");
        uint256 srcChain=block.chainid;

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i].chainId != srcChain) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
            }
        }

    }
}
