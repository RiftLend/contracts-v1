// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.25;

library OFTLogic {
    ///@dev modification in this one also needs modification in decodeMessage below

    function encodeMessage(address _receiverOfUnderlying, uint256 _amount)
        public
        pure
        returns (bytes memory _message)
    {
        _message = abi.encode(_receiverOfUnderlying, _amount);
    }

    function decodeMessage(bytes memory _message)
        public
        pure
        returns (address _receiverOfUnderlying, uint256 _amount, address _oftCaller)
    {
        // the oft's _buildMsgAndOptions is used by _send method that encodes the passed messagein following way
        // abi.encodePacked(_sendTo, _amountShared, addressToBytes32(msg.sender), _composeMsg)
        (,, bytes32 oftCaller, bytes memory encoded_message) = abi.decode(_message, (address, uint256, bytes32, bytes));
        _oftCaller = address(uint160(uint256(oftCaller)));
        (_receiverOfUnderlying, _amount) = abi.decode(encoded_message, (address, uint256));
    }

    function decodeSubLzMessage(bytes memory encoded_message)
        public
        pure
        returns (address _receiverOfUnderlying, uint256 _amount)
    {
        (_receiverOfUnderlying, _amount) = abi.decode(encoded_message, (address, uint256));
    }
}
