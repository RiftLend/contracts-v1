// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./ICrossL2Inbox.sol";

enum ValidationMode {
    CUSTOM,
    CROSS_L2_INBOX,
    CROSS_L2_PROVER_EVENT,
    CROSS_L2_PROVER_RECEIPT
}

interface IValidater {

    function initialize(address _crossL2Prover) external;

    function validate(
        ValidationMode _mode,
        Identifier calldata _identifier,
        bytes[] calldata _data,
        uint256[] calldata _logIndex,
        bytes calldata _proof
    ) external;
}