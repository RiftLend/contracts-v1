pragma solidity ^0.8.0;

contract MockLayerZeroEndpointV2 {
    address delegate;

    constructor(uint32 uid, address _delegate) {}

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}
