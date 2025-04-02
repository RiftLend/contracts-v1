// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Predeploys} from "./Predeploys.sol";

import "../interfaces/ICrossL2Inbox.sol";
import {ICrossL2Prover} from "../interfaces/ICrossL2Prover.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

enum ValidationMode {
    CUSTOM,
    CROSS_L2_INBOX,
    CROSS_L2_PROVER_EVENT
}

contract EventValidator is Initializable, Ownable {
    ICrossL2Prover private crossL2Prover;
    address router;
    address lendingPool;

    event logger(string message);
    event loggerUint(uint256);
    event loggerBytes32(bytes32);
    event loggerBytes(bytes);

    constructor(address ownerAddr) Ownable(ownerAddr) {
        _transferOwnership(ownerAddr);
    }

    function initialize(address _crossL2Prover, address _router, address _lendingPool) external initializer onlyOwner {
        crossL2Prover = ICrossL2Prover(_crossL2Prover);
        router = _router;
        lendingPool = _lendingPool;
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
        } else if (_mode == ValidationMode.CROSS_L2_PROVER_EVENT) {
            /// @dev use ICrossL2Prover to validate message
            (, address sourceContract, bytes memory topics, bytes memory unindexedData) =
                crossL2Prover.validateEvent(_proof);

            // Step 2: Split concatenated topics into individual 32-byte values
            bytes32[] memory topicsArray = new bytes32[](3); // [eventSig, sender, hashedKey]

            // // Use assembly for efficient memory operations when splitting topics
            assembly {
                // Skip first 32 bytes (length prefix of bytes array)
                let topicsPtr := add(topics, 32)

                // Load each 32-byte topic into the array
                // topicsArray structure: [eventSig, sender, hashedKey]
                for { let i := 0 } lt(i, 3) { i := add(i, 1) } {
                    mstore(add(add(topicsArray, 32), mul(i, 32)), mload(add(topicsPtr, mul(i, 32))))
                }
            }

            require(topicsArray[0] == bytes32(_data[0]), "Invalid event signature");
            bytes memory dataSlice = _data[0][32:];
            require(keccak256(unindexedData) == keccak256(dataSlice), "Malformed data");
            require(sourceContract == lendingPool || sourceContract == router, "Malformed origin");
        }
    }
}
