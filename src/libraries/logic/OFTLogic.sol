// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.25;

import {OFTMsgCodec} from "src/libraries/helpers/layerzero/OFTMsgCodec.sol";

library OFTLogic {
    using OFTMsgCodec for bytes;

    ///@dev modification in encodeMessage also needs modification in decodeMessage below

    function encodeMessage(address _receiverOfUnderlying, uint256 _amount)
        public
        pure
        returns (bytes memory _message)
    {
        _message = abi.encode(_receiverOfUnderlying, _amount);
    }

    function decodeMessage(bytes calldata _message)
        public
        pure
        returns (address _receiverOfUnderlying, uint256 _amount, address _oftCaller)
    {
        (_oftCaller, _receiverOfUnderlying, _amount) =
            abi.decode(OFTMsgCodec.composeMsg(_message), (address, address, uint256));
    }
}
