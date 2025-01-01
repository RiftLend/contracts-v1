// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.22;

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {IRVaultAsset} from "./interfaces/IRVaultAsset.sol";
import {
    Origin, MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
// packages/contracts/lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol
import {OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {OFTAdapter} from "./libraries/helpers/layerzero/OFTAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFTLogic} from "./libraries/logic/OFTLogic.sol";

contract SuperAssetAdapter is OFTAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(address => address) public underlyingToPoolAddressProvider;
    address public underlyingAsset;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Errors                                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidPool();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Constructor                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address rVaultAsset, address _lzEndpoint, address _underlyingAsset)
        OFTAdapter(rVaultAsset, _lzEndpoint, msg.sender)
    {
        underlyingAsset = _underlyingAsset;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  External Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, bytes calldata _extraData)
        external
        payable
    {
        // Ensures that only the endpoint can attempt to lzReceive() messages to this OApp.
        if (address(endpoint) != msg.sender) revert OnlyEndpoint(msg.sender);

        // Ensure that the sender matches the expected peer for the source endpoint.
        if (_getPeerOrRevert(_origin.srcEid) != _origin.sender) revert OnlyPeer(_origin.srcEid, _origin.sender);

        (, uint256 amount) = OFTLogic.decodeMessage(_message);

        (, address rVaultAsset) =
            ILendingPoolAddressesProvider(underlyingToPoolAddressProvider[underlyingAsset]).getRVaultAsset();

        if (rVaultAsset == address(0)) revert InvalidPool();

        _credit(rVaultAsset, amount, 0);
        IRVaultAsset(rVaultAsset).lzReceive(_origin, _guid, _message, address(0), _extraData);

        // super._lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    function setUnderlyingToPoolAddressProvider(address asset, address poolAddressProvider) external onlyOwner {
        underlyingToPoolAddressProvider[asset] = poolAddressProvider;
    }
}
