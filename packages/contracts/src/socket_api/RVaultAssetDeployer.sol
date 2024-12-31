// // SPDX-License-Identifier: GPL-3.0
// pragma solidity >=0.7.0 <0.9.0;

// import {RVaultAsset} from "../RVaultAsset.sol";
// import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

// import "socket-protocol/contracts/base/AppDeployerBase.sol";

// contract RVaultAssetDeployer is AppDeployerBase {
//     bytes32 public rVaultAsset = _createContractId("rVaultAsset");

//     constructor(
//         address addressResolver_,
//         FeesData memory feesData_,
//         ILendingPoolAddressesProvider provider_,
//         address admin_,
//         address lzEndpoint_,
//         address delegate_,
//         address _rVaultAssetSocketAppGateway
//     ) AppDeployerBase(addressResolver_) {
//         creationCodeWithArgs[rVaultAsset] = abi.encodePacked(
//             type(RVaultAsset).creationCode,
//             abi.encode(provider_, admin_, lzEndpoint_, delegate_, _rVaultAssetSocketAppGateway)
//         );
//         _setFeesData(feesData_);
//     }

//     function deployContracts(uint32 chainSlug) external async {
//         _deploy(rVaultAsset, chainSlug);
//     }

//     function initialize(uint32 chainSlug) public override async {
//         address socket = getSocketAddress(chainSlug);
//         address rVaultAssetForwarder = forwarderAddresses[rVaultAsset][chainSlug];
//         rVaultAsset(rVaultAssetForwarder).setSocket(socket);
//     }

//     function setFees(FeesData memory feesData_) public {
//         feesData = feesData_;
//     }
// }
