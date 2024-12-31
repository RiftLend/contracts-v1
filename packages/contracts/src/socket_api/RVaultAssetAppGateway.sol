// // SPDX-License-Identifier: GPL-3.0
// pragma solidity >=0.7.0 <0.9.0;

// import "socket-protocol/contracts/base/AppGatewayBase.sol";
// import {RVaultAsset} from "../RVaultAsset.sol";
// import {DataTypes} from "../libraries/types/DataTypes.sol";

// contract RVaultAssetAppGateway is AppGatewayBase {
//     event Bridged(bytes32 asyncId);

//     constructor(address _addressResolver, address deployerContract_, FeesData memory feesData_)
//         AppGatewayBase(_addressResolver)
//     {
//         addressResolver.setContractsToGateways(deployerContract_);
//         _setFeesData(feesData_);
//     }

//     function checkBalance(bytes memory data, bytes memory returnData) external onlyPromises {
//         (DataTypes.UserOrder memory order, bytes32 asyncId) = abi.decode(data, (DataTypes.UserOrder, bytes32));

//         uint256 balance = abi.decode(returnData, (uint256));
//         if (balance < order.srcAmount) {
//             _revertTx(asyncId);
//             return;
//         }
//         _unlockTokens(order.srcToken, order.user, order.srcAmount);
//     }

//     function _unlockTokens(address srcToken, address user, uint256 amount) internal async {
//         ISuperToken(srcToken).unlockTokens(user, amount);
//     }

//     function bridge(bytes memory _order) external async returns (bytes32 asyncId) {
//         DataTypes.UserOrder memory order = abi.decode(_order, (DataTypes.UserOrder));
//         asyncId = _getCurrentAsyncId();
//         ISuperToken(order.srcToken).lockTokens(order.user, order.srcAmount);

//         _readCallOn();
//         // goes to forwarder and deploys promise and stores it
//         ISuperToken(order.srcToken).balanceOf(order.user);
//         IPromise(order.srcToken).then(this.checkBalance.selector, abi.encode(order, asyncId));

//         _readCallOff();
//         ISuperToken(order.dstToken).mint(order.user, order.srcAmount);
//         ISuperToken(order.srcToken).burn(order.user, order.srcAmount);

//         emit Bridged(asyncId);
//     }

//     function setFees(FeesData memory feesData_) public {
//         feesData = feesData_;
//     }
// }
