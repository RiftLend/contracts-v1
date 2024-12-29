// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract SuperAssetAdapter is OFTAdapter {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapter(_token, _lzEndpoint, msg.sender) Ownable(msg.sender) {}
}
