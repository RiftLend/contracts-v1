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

contract SuperAssetAdapter is OFTAdapter {
    constructor(address rVaultAsset, address _lzEndpoint) OFTAdapter(rVaultAsset, _lzEndpoint, msg.sender) {}

    mapping(address => address) public underlyingToPoolAddressProvider;

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        // Validate crosschain message's authenticity
        (,, address _underlyingAsset) = abi.decode(_message, (uint64, address, address));

        (bytes32 lendingPool_type, address rVaultAsset) =
            ILendingPoolAddressesProvider(underlyingToPoolAddressProvider[_underlyingAsset]).getRVaultAsset();
        require(rVaultAsset == address(0), "InvalidPool");
        IRVaultAsset(rVaultAsset).lzReceive(_origin, _guid, _message, _executor, _extraData);
        // TODO check _credit to is rvault or nto 

        // super._lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    function setUnderlyingToPoolAddressProvider(address asset, address poolAddressProvider) external onlyOwner {
        underlyingToPoolAddressProvider[asset] = poolAddressProvider;
    }
}
