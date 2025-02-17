// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {LendingPool} from "src/LendingPool.sol";
import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
import {LendingRateOracle} from "src/LendingRateOracle.sol";
import {SuperAsset} from "src/SuperAsset.sol";
import {RToken} from "src/tokenization/RToken.sol";
import {VariableDebtToken} from "src/tokenization/VariableDebtToken.sol";
import {L2NativeSuperchainERC20} from "src/libraries/op/L2NativeSuperchainERC20.sol";
import {Router} from "src/Router.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockLayerZeroEndpointV2} from "test/utils/MockLayerZeroEndpointV2.sol";
import {TestERC20} from "test/utils/TestERC20.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {LendingPoolCollateralManager} from "src/LendingPoolCollateralManager.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeploymentContractSizes is Script {
    function run() public pure {
        console.log("TestERC20 creation code size:", type(TestERC20).creationCode.length);
        console.log("EventValidator creation code size:", type(EventValidator).creationCode.length);
        console.log("SuperAsset creation code size:", type(SuperAsset).creationCode.length);
        console.log("RVaultAsset creation code size:", type(RVaultAsset).creationCode.length);
        console.log("ProxyAdmin creation code size:", type(ProxyAdmin).creationCode.length);
        console.log(
            "LendingPoolAddressesProvider creation code size:", type(LendingPoolAddressesProvider).creationCode.length
        );
        console.log("LendingPool creation code size:", type(LendingPool).creationCode.length);
        console.log("LendingPoolConfigurator creation code size:", type(LendingPoolConfigurator).creationCode.length);
        console.log(
            "DefaultReserveInterestRateStrategy creation code size:",
            type(DefaultReserveInterestRateStrategy).creationCode.length
        );
        console.log("MockPriceOracle creation code size:", type(MockPriceOracle).creationCode.length);
        console.log(
            "LendingPoolCollateralManager creation code size:", type(LendingPoolCollateralManager).creationCode.length
        );
        console.log("Router creation code size:", type(Router).creationCode.length);
        console.log(
            "TransparentUpgradeableProxy creation code size:", type(TransparentUpgradeableProxy).creationCode.length
        );
        console.log("RToken creation code size:", type(RToken).creationCode.length);
        console.log("VariableDebtToken creation code size:", type(VariableDebtToken).creationCode.length);
    }
}
