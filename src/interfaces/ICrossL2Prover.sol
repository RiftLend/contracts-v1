// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

interface ICrossL2Prover {
    function validateEvent(uint256 logIndex, bytes calldata proof)
        external
        returns (bytes32 chainId, address emittingContract, bytes[] memory topics, bytes memory unindexedData);
    function validateReceipt(bytes calldata proof)
        external
        view
        returns (bytes32 chainID, bytes memory rlpEncodedBytes);
    function parseLog(uint256 logIndex, bytes calldata rlpEncodedBytes)
        external
        view
        returns (address emittingContract, bytes[] memory topics, bytes memory unindexedData);
}
