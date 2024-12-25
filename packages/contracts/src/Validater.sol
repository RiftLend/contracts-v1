// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./interfaces/ICrossL2Inbox.sol";
import {Predeploys} from "./libraries/Predeploys.sol";
import {ICrossL2Prover} from "./interfaces/ICrossL2Prover.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import "./interfaces/IValidater.sol";

contract Validater is Initializable {

    ICrossL2Prover private crossL2Prover;
    
    event Initialized(address crossL2Prover);

    function initialize(address _crossL2Prover) public initializer {
        crossL2Prover = ICrossL2Prover(_crossL2Prover);
        emit Initialized(_crossL2Prover);
    }

    function validate(
        ValidationMode _mode,
        Identifier calldata _identifier,
        bytes[] calldata _data,
        uint256[] calldata _logIndex,
        bytes calldata _proof
    ) external {
        /// @dev use ICrossL2Inbox to validate message
        if (_mode == ValidationMode.CROSS_L2_INBOX) {
            if (_identifier.origin != address(this)) {
                revert("!origin");
            }
            ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data[0]));
        }
        if (_mode == ValidationMode.CROSS_L2_PROVER_EVENT) {
            /// @dev use ICrossL2Prover to validate message
            (, address emittingContract, bytes[] memory topics, bytes memory unindexedData) =
                crossL2Prover.validateEvent(_logIndex[0], _proof);
            if (emittingContract != address(this)) {
                revert("!origin");
            }
            if (keccak256(abi.encode(topics[0], unindexedData)) != keccak256(_data[0])) {
                revert("!data");
            }
        }
        if (_mode == ValidationMode.CROSS_L2_PROVER_RECEIPT) {
            /// @dev use ICrossL2Prover to validate receipt
            (, bytes memory rlpEncodedBytes) = crossL2Prover.validateReceipt(_proof);
            for (uint256 i = 0; i < _logIndex.length; i++) {
                (address emittingContract, bytes[] memory topics, bytes memory unindexedData) =
                    crossL2Prover.parseLog(_logIndex[i], rlpEncodedBytes);
                if (emittingContract != address(this)) {
                    revert("!origin");
                }
                if (keccak256(abi.encode(topics[0], unindexedData)) != keccak256(_data[i])) {
                    revert("!data");
                }
            }
        }
    }

}