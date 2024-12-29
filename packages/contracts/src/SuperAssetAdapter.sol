// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.22;
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IRVaultAsset} from "./interfaces/IRVaultAsset.sol";


import {OFTAdapter} from '@layerzerolabs/oft-evm/contracts/OFTAdapter.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {MessagingFee, MessagingParams, MessagingReceipt, Origin} from '@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol';

contract SuperAssetAdapter is OFTAdapter {
  constructor(
    address rVaultAsset,
    address _lzEndpoint
  ) OFTAdapter(rVaultAsset, _lzEndpoint, msg.sender) Ownable(msg.sender) {}

  mapping(address => address) public underlying_to_pool;

  struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
  }

  function lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
  )
    external
    payable
    override
    returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
  {
    // Validate crosschain message's authenticity

    address _underlyingAsset = OFTComposeMsgCodec._underlyingAsset(message);

    (bytes32 lendingPool_type, address rVaultAsset) = ILendingPool(
      underlying_to_pool[_underlyingAsset]
    ).getRVaultAsset();
    require(rVaultAsset == address(0), 'InvalidPool');
    IRVaultAsset(rVaultAsset).lzReceive(
      _origin,
      _guid,
      _message,
      _executor,
      _extraData
    );
    super._lzReceive(_origin, _guid, _message, _executor, _extraData);
  }
}
