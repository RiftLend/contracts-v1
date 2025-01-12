pragma solidity ^0.8.0;

// Todo: Make it fully compliant with the LayerZero standard

contract MockLayerZeroEndpointV2 {
    address delegate;

    constructor(uint32 uid, address _delegate) {}

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}
