// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Pausable} from "@openzeppelin/contracts-v5/utils/Pausable.sol";
import {ICrossL2Inbox} from "../../../interfaces/ICrossL2Inbox.sol";
import {Predeploys} from "../../../libraries/Predeploys.sol";
import {Identifier} from "../../../interfaces/ICrossL2Inbox.sol";

error IdOriginNotSuperPausable();
error DataNotCrosschainPauseTransfer();
error PauseStateNotInSync();
error NoPauseStateChange();

contract SuperPausable is Pausable {
    event CrosschainPauseStateChanged(bool previousState, bool newState);

    bytes32 public constant InitiateCrosschainPauseTransfer = keccak256("CrosschainPauseStateChange(bool,bool)");

    /**
     * @notice Updates the pause state of the contract from a cross-chain message.
     * @param _identifier The identifier of the cross-chain message.
     * @param _data The data of the cross-chain message.
     */
    function updateCrosschainPauseState(Identifier calldata _identifier, bytes calldata _data) external virtual {
        if (_identifier.origin != address(this)) revert IdOriginNotSuperPausable();
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data));

        // Decode `CrosschainPauseStateChange` event
        bytes32 selector = abi.decode(_data[:32], (bytes32));
        if (selector != InitiateCrosschainPauseTransfer) revert DataNotCrosschainPauseTransfer();
        (bool previousState, bool newState) = abi.decode(_data[32:], (bool, bool));
        if (previousState != paused()) revert PauseStateNotInSync();
        if (newState == paused()) revert NoPauseStateChange();

        if (_identifier.chainId != block.chainid) {
            if (newState) {
                super._pause();
            } else {
                super._unpause();
            }
        }

        emit CrosschainPauseStateChanged(previousState, newState);
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual override whenNotPaused {
        super._pause();
        emit CrosschainPauseStateChanged(false, true);
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual override whenPaused {
        super._unpause();
        emit CrosschainPauseStateChanged(true, false);
    }
}
