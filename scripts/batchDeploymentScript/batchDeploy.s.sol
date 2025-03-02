// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/* 
 ____  _  __ _   _                   _    ____             _                                  _       
|  _ \(_)/ _| |_| |    ___ _ __   __| |  |  _ \  ___ _ __ | | ___  _   _ _ __ ___   ___ _ __ | |_ ___ 
| |_) | | |_| __| |   / _ \ '_ \ / _` |  | | | |/ _ \ '_ \| |/ _ \| | | | '_ ` _ \ / _ \ '_ \| __/ __|
|  _ <| |  _| |_| |__|  __/ | | | (_| |  | |_| |  __/ |_) | | (_) | |_| | | | | | |  __/ | | | |_\__ \
|_| \_\_|_|  \__|_____\___|_| |_|\__,_|  |____/ \___||.__/|_|\___/ \__, |_| |_| |_|\___|_| |_|\__|___/
                                                     |_|           |___/                                                                                                      
                B A T C H    V E R S I O N
*/

/* ╔════════════════════════════════════════╗
   ║       INTERFACES & CONFIGURATION       ║
   ╚════════════════════════════════════════╝ */

import {Script, console} from "forge-std/Script.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {LendingPool} from "src/LendingPool.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";
import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {Vm} from "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";

/* ╔════════════════════════════════════════╗
   ║         BATCH DEPLOYERS IMPORT         ║
   ╚════════════════════════════════════════╝ */
import {BatchDeployer1, BatchDeployer2, BatchDeployer3, BatchDeployer4, Create2Helper} from "./BatchDeployers.sol";
import {BatchDataTypes} from "./BatchDataTypes.sol";
import {SystemConfigManager} from "./SystemConfigManager.sol";

/* 
╭─────────────────────────────╮
│      RIFTLEND DEPLOYER      │  ✨ Deployment & Configuration ✨
╰─────────────────────────────╯
*/

contract MainDeployer is Script {
    string deployConfig;
    BatchDataTypes.BatchAddressesSet public batchAddressesSet;
    BatchDataTypes.MainDeployerLocalVars public vars;
    BatchDataTypes.BatchDeployerSet public batchDeployerSet;
    LendingPoolConfigurator public configurator;
    string public targetChain;

    /* 
    ╔════════════════════════════╗
    ║         RUN METHoD         ║   🧪 Script Entry Point
    ╚════════════════════════════╝
    */

    function run() public {
        targetChain = getConfigChainAlias();
        console.log("chain alias:", targetChain);

        // 🌐 MAINNET READY: Load deploy configuration
        deployConfig = vm.readFile(string.concat(vm.projectRoot(), "/configs/deploy-config.toml"));

        // ╔══════════════════════════════╗
        // ║ PARSE CONFIGURATION PARAMS   ║  (Parameters Discovery)
        // ╚══════════════════════════════╝
        parseDeployConfig();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // ╔══════════════════════════════╗
        // ║  DEPLOY BATCHES PHASE        ║  🚀 Deploying All Batch Contracts...
        // ╚══════════════════════════════╝
        deployBatches();

        // ╔══════════════════════════════╗
        // ║ CONFIGURATION PHASE          ║  🔥 System Configuration
        // ╚══════════════════════════════╝

        configureSystem();

        vm.stopBroadcast();

        // // ╔══════════════════════════════╗
        // // ║ OUTPUT DEPLOYMENT RESULTS    ║  🎉 Deployment Complete!
        // // ╚══════════════════════════════╝
        outputDeploymentResults();
    }

    /* 
    ╔════════════════════════════╗
    ║  PARSE DEPLOY CONFIG FILE  ║
    ╚════════════════════════════╝
    */
    function parseDeployConfig() internal {
        vars.crossL2ProverAddress =
            vm.parseTomlAddress(deployConfig, string.concat(".forks.", targetChain, "_cross_l2_prover_address"));
        vars.currentChainWethAddress = vm.parseTomlAddress(deployConfig, string.concat(".forks.", targetChain, "_weth"));
        vars.poolAdmin = vm.parseTomlAddress(deployConfig, ".pool_admin.address");
        vars.ownerAddress = vm.parseTomlAddress(deployConfig, ".owner.address");

        vars.underlyingDecimals = uint8(vm.parseTomlUint(deployConfig, ".underlying.decimals"));
        vars.lpType = keccak256(bytes(vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.lpType")));
    }

    /* 
    ╔════════════════════════════╗
    ║   DEPLOY BATCHES PHASE     ║  🚀 Deploying Batches
    ╚════════════════════════════╝
    */
    SystemConfigManager systemConfigManager;

    function deployBatches() internal {
        string memory systemConfigManagerSalt = "systemConfigManager";
        string memory batchDeployer1Salt = "batchDeployer1";
        string memory batchDeployer2Salt = "batchDeployer2";
        string memory batchDeployer3Salt = "batchDeployer3";
        string memory batchDeployer4Salt = "batchDeployer4";

        systemConfigManager = SystemConfigManager(
            Create2Helper.deployContractWithArgs(
                "SystemConfigManager", systemConfigManagerSalt, type(SystemConfigManager).creationCode, abi.encode(
                    vm.parseTomlAddress(deployConfig, ".owner.address")
                )
            )
        );
        address initialOwner = address(systemConfigManager);

        // Batch 1 deployer: Underlying, Oracle, and Proxy-related contracts.
        batchDeployerSet.bd1 = BatchDeployer1(
            Create2Helper.deployContractWithArgs(
                "BatchDeployer1",
                batchDeployer1Salt,
                type(BatchDeployer1).creationCode,
                abi.encode(
                    BatchDataTypes.Batch1Params(
                        vm.parseTomlString(deployConfig, ".underlying.salt"),
                        initialOwner,
                        vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.marketId"),
                        vars.lpType,
                        vm.parseTomlString(deployConfig, ".super_token.salt"),
                        vm.parseTomlString(deployConfig, ".event_validator.salt"),
                        vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.salt"),
                        vm.parseTomlString(deployConfig, ".price_oracle.salt"),
                        vm.parseTomlAddress(deployConfig, ".owner.address"),
                        vm.parseTomlString(deployConfig, ".proxy_admin.salt"),
                        vm.parseTomlString(deployConfig, ".default_reserve_interest_rate_strategy.salt")
                    )
                )
            )
        );

        BatchDeployer1.Addresses memory a1 = batchDeployerSet.bd1.getDeployedAddresses();
        batchAddressesSet.batch1Addrs = BatchDataTypes.Batch1Addresses(
            a1.underlying,
            a1.eventValidator,
            a1.superAsset,
            a1.proxyAdmin,
            a1.lendingPoolAddressesProvider,
            a1.defaultReserveInterestRateStrategy,
            a1.mockPriceOracle
        );

        // // Batch 2 deployer: LendingPool and LendingPoolConfigurator.
        batchDeployerSet.bd2 = BatchDeployer2(
            Create2Helper.deployContractWithArgs(
                "BatchDeployer2",
                batchDeployer2Salt,
                type(BatchDeployer2).creationCode,
                abi.encode(
                    vm.parseTomlString(deployConfig, ".lending_pool.salt"),
                    vm.parseTomlString(deployConfig, ".lending_pool_configurator.salt")
                )
            )
        );

        BatchDeployer2.Addresses memory a2 = batchDeployerSet.bd2.getDeployedAddresses();
        batchAddressesSet.batch2Addrs = BatchDataTypes.Batch2Addresses({
            lendingPoolImpl: a2.lendingPoolImpl,
            lendingPoolConfigurator: a2.lendingPoolConfigurator
        });

        // Batch 3 deployer: RVaultAsset, RToken, and VariableDebtToken.
        batchDeployerSet.bd3 = BatchDeployer3(
            Create2Helper.deployContractWithArgs(
                "BatchDeployer3",
                batchDeployer3Salt,
                type(BatchDeployer3).creationCode,
                abi.encode(
                    vm.parseTomlString(deployConfig, ".rvault_asset.salt"),
                    vm.parseTomlString(deployConfig, ".rToken.salt"),
                    vm.parseTomlString(deployConfig, ".variable_debt_token.salt"),
                    initialOwner
                )
            )
        );

        BatchDeployer3.Addresses memory a3 = batchDeployerSet.bd3.getDeployedAddresses();
        batchAddressesSet.batch3Addrs = BatchDataTypes.Batch3Addresses({
            rVaultAsset: a3.rVaultAsset,
            rToken: a3.rToken,
            variableDebtToken: a3.variableDebtToken
        });

        // Batch 4 deployer: LendingPoolCollateralManager & Router (via proxy).
        batchDeployerSet.bd4 = BatchDeployer4(
            Create2Helper.deployContractWithArgs(
                "BatchDeployer4",
                batchDeployer4Salt,
                type(BatchDeployer4).creationCode,
                abi.encode(
                    vm.parseTomlString(deployConfig, ".router.salt"),
                    vm.parseTomlString(deployConfig, ".lending_pool_collateral_manager.salt")
                )
            )
        );

        BatchDeployer4.Addresses memory a4 = batchDeployerSet.bd4.getDeployedAddresses();
        batchAddressesSet.batch4Addrs = BatchDataTypes.Batch4Addresses({
            lendingPoolCollateralManager: a4.lendingPoolCollateralManager,
            routerImpl: a4.router,
            proxyRouter: address(0) //updated later
        });
    }

    /* 
    ╔════════════════════════════╗
    ║   CONFIGURATION PHASE      ║  🔥 System Configuration
    ╚════════════════════════════╝
    */
    function configureSystem() internal {
        // Retrieve the LendingPoolAddressesProvider from Batch 1.
        vars.lpProvider = ILendingPoolAddressesProvider(batchAddressesSet.batch1Addrs.lendingPoolAddressesProvider);

        ILendingPoolConfigurator.InitReserveInput[] memory reserveInputs =
            new ILendingPoolConfigurator.InitReserveInput[](1);
        reserveInputs[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenName: vm.parseTomlString(deployConfig, ".rToken.name"),
            rTokenSymbol: vm.parseTomlString(deployConfig, ".rToken.symbol"),
            variableDebtTokenImpl: batchAddressesSet.batch3Addrs.variableDebtToken,
            variableDebtTokenName: vm.parseTomlString(deployConfig, ".variable_debt_token.name"),
            variableDebtTokenSymbol: vm.parseTomlString(deployConfig, ".variable_debt_token.symbol"),
            interestRateStrategyAddress: batchAddressesSet.batch1Addrs.defaultReserveInterestRateStrategy,
            treasury: vm.parseTomlAddress(deployConfig, ".treasury.address"),
            incentivesController: vm.parseTomlAddress(deployConfig, ".incentives_controller.address"),
            superAsset: batchAddressesSet.batch1Addrs.superAsset,
            underlyingAsset: batchAddressesSet.batch3Addrs.rVaultAsset,
            underlyingAssetDecimals: uint8(vm.parseTomlUint(deployConfig, ".underlying.decimals")),
            underlyingAssetName: vm.parseTomlString(deployConfig, ".underlying.name"),
            params: "v1",
            salt: "initial",
            rTokenImpl: batchAddressesSet.batch3Addrs.rToken,
            eventValidator: batchAddressesSet.batch1Addrs.eventValidator
        });
        RVaultAssetInitializeParams memory rvaultAssetInitializeParams = RVaultAssetInitializeParams(
            batchAddressesSet.batch1Addrs.superAsset,
            vars.lpProvider,
            vm.parseTomlAddress(deployConfig, string.concat(".forks.", targetChain, "_lz_endpoint_v2")),
            vm.parseTomlAddress(deployConfig, string.concat(".forks.", targetChain, "_lz_delegate")),
            vm.parseTomlString(deployConfig, ".rvault_asset.name"),
            vm.parseTomlString(deployConfig, ".rvault_asset.symbol"),
            vars.underlyingDecimals,
            vm.parseTomlUint(deployConfig, ".rvault_asset.withdraw_cool_down_period"),
            vm.parseTomlUint(deployConfig, ".rvault_asset.max_deposit_limit"),
            uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_receive_gas_limit")),
            uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_compose_gas_limit")),
            vm.parseTomlAddress(deployConfig, ".owner.address")
        );

        BatchDataTypes.SuperAssetInitParams memory superAssetInitParams = BatchDataTypes.SuperAssetInitParams(
            batchAddressesSet.batch1Addrs.underlying,
            vm.parseTomlString(deployConfig, ".super_token.name"),
            vm.parseTomlString(deployConfig, ".super_token.symbol"),
            vars.currentChainWethAddress
        );

        // abi.encode(
        //         params.underlyingName, params.underlyingSymbol, params.underlyingDecimals, params.owner
        //     )
        BatchDataTypes.UnderlyingInitParams memory underlyingInitParams = BatchDataTypes.UnderlyingInitParams(
            vm.parseTomlString(deployConfig, ".underlying.name"),
            vm.parseTomlString(deployConfig, ".underlying.symbol"),
            vars.underlyingDecimals,
            vm.parseTomlAddress(deployConfig, ".owner.address")
        );

        BatchDataTypes.DefaultStrategyInitParams memory strategyParams = BatchDataTypes.DefaultStrategyInitParams(
            ILendingPoolAddressesProvider(batchAddressesSet.batch1Addrs.lendingPoolAddressesProvider),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.optimalUtilizationRate"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.baseVariableBorrowRate"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope1"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope2")
        );
        vars.relayers = new address[](vm.parseTomlUint(deployConfig, ".relayers.total"));
        for (uint256 i = 1; i <= vars.relayers.length; i++) {
            vars.relayers[i-1] =
                vm.parseTomlAddress(deployConfig, string.concat(".relayers.address", Strings.toString(i)));
        }

        (batchAddressesSet.batch4Addrs.proxyRouter) = systemConfigManager.initialize(
            vars,
            batchAddressesSet,
            reserveInputs,
            strategyParams,
            underlyingInitParams,
            rvaultAssetInitializeParams,
            superAssetInitParams
        );

        vars.proxyConfigurator = LendingPoolConfigurator(vars.lpProvider.getLendingPoolConfigurator());
        LendingPool proxyLp = LendingPool(ILendingPoolAddressesProvider(vars.lpProvider).getLendingPool());
        vars.proxyLp = proxyLp;

        // Get proxy addresses for initialized tokens
        DataTypes.ReserveData memory reserveData =
            vars.proxyLp.getReserveData(batchAddressesSet.batch3Addrs.rVaultAsset);
        batchAddressesSet.batch3Addrs.rToken = reserveData.rTokenAddress;
        batchAddressesSet.batch3Addrs.variableDebtToken = reserveData.variableDebtTokenAddress;
    }

    /* 
    ╔════════════════════════════════╗
    ║   OUTPUT DEPLOYMENT RESULTS    ║   🎉 Deployment Complete!
    ╚════════════════════════════════╝
    */
    function outputDeploymentResults() internal {
        console.log("  Underlying:", batchAddressesSet.batch1Addrs.underlying);
        console.log("  SuperAsset:", batchAddressesSet.batch1Addrs.superAsset);
        console.log("  RVaultAsset:", batchAddressesSet.batch3Addrs.rVaultAsset);
        console.log("  RToken:", batchAddressesSet.batch3Addrs.rToken);

        console.log("  LendingPool:", address(vars.proxyLp));
        console.log("  LendingPoolConfigurator:", batchAddressesSet.batch2Addrs.lendingPoolConfigurator);
        console.log("  LendingPoolAddressesProvider:", batchAddressesSet.batch1Addrs.lendingPoolAddressesProvider);
        console.log("  LendingPoolCollateralManager:", batchAddressesSet.batch4Addrs.lendingPoolCollateralManager);

        console.log("  Router :", batchAddressesSet.batch4Addrs.proxyRouter);

        console.log(
            "  DefaultReserveInterestRateStrategy:", batchAddressesSet.batch1Addrs.defaultReserveInterestRateStrategy
        );
        console.log("  EventValidator:", batchAddressesSet.batch1Addrs.eventValidator);
        console.log("  ProxyAdmin:", batchAddressesSet.batch1Addrs.proxyAdmin);

        console.log("  MockPriceOracle:", batchAddressesSet.batch1Addrs.mockPriceOracle);
        console.log("  VariableDebtToken:", batchAddressesSet.batch3Addrs.variableDebtToken);

        string memory deploymentFile = "deployment.json";

        string memory obj = "result";

        vm.serializeAddress(obj, "Underlying", batchAddressesSet.batch1Addrs.underlying);
        vm.serializeAddress(obj, "SuperAsset", batchAddressesSet.batch1Addrs.superAsset);
        vm.serializeAddress(obj, "RVaultAsset", batchAddressesSet.batch3Addrs.rVaultAsset);
        vm.serializeAddress(obj, "RToken", batchAddressesSet.batch3Addrs.rToken);
        vm.serializeAddress(obj, "VariableDebtToken", batchAddressesSet.batch3Addrs.variableDebtToken);
        vm.serializeAddress(
            obj, "LendingPoolAddressesProvider", batchAddressesSet.batch1Addrs.lendingPoolAddressesProvider
        );
        vm.serializeAddress(obj, "LendingPool", address(vars.proxyLp));
        vm.serializeAddress(obj, "LendingPoolConfigurator", batchAddressesSet.batch2Addrs.lendingPoolConfigurator);
        vm.serializeAddress(obj, "Router", batchAddressesSet.batch4Addrs.proxyRouter);
        vm.serializeAddress(
            obj, "LendingPoolCollateralManager", batchAddressesSet.batch4Addrs.lendingPoolCollateralManager
        );
        vm.serializeAddress(
            obj, "DefaultReserveInterestRateStrategy", batchAddressesSet.batch1Addrs.defaultReserveInterestRateStrategy
        );
        vm.serializeAddress(obj, "MockPriceOracle", batchAddressesSet.batch1Addrs.mockPriceOracle);
        vm.serializeAddress(obj, "EventValidator", batchAddressesSet.batch1Addrs.eventValidator);
        vm.serializeAddress(obj, "ProxyAdmin", batchAddressesSet.batch1Addrs.proxyAdmin);

        string memory jsonOutput =
            vm.serializeAddress(obj, "Owner", vm.parseTomlAddress(deployConfig, ".owner.address"));
        vm.writeJson(jsonOutput, deploymentFile);
    }

    /* 
    ╔══════════════════════════════════════╗
    ║  GET CONFIG CHAIN ALIAS FUNCTION     ║   ( Chain Alias Owl 🦉)
    ╚══════════════════════════════════════╝
    */

    function getConfigChainAlias() internal view returns (string memory chainAlias) {
        // ────── Chain Selector ──────
        if (block.chainid == 1) {
            chainAlias = "chain_a";
        } else if (block.chainid == 10) {
            chainAlias = "chain_b";
        } else if (block.chainid == 11155420) {
            chainAlias = "chain_test_a";
        } else if (block.chainid == 84532) {
            chainAlias = "chain_test_b";
        } else if (block.chainid == 1301) {
            chainAlias = "chain_test_c";
        } else if (block.chainid == 421614) {
            chainAlias = "chain_test_d";
        } else if (block.chainid == 11155111) {
            chainAlias = "chain_test_e";
        } else {
            require(false, "UnsupportedChain from script");
        }
    }
}
