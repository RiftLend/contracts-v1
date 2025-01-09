// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.0;

import {SendParam, OFTReceipt} from "../libraries/helpers/layerzero/IOFT.sol";
import "../libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";

interface ISuperAssetAdapter is ILayerZeroEndpointV2 {
    /**
     * @notice Executes the send() operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The fee information supplied by the caller.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds from fees etc. on the src.
     * @return receipt The LayerZero messaging receipt from the send() operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(SendParam memory _sendParam, MessagingFee memory _fee, address payable _refundAddress)
        external
        payable
        returns (MessagingReceipt memory, OFTReceipt memory);

    /**
     * @notice Provides a quote for the send() operation.
     * @param _sendParam The parameters for the send() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingFee: LayerZero msg fee
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     */
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);
    function setPeer(uint32 _eid, bytes32 _peer) external;
}
