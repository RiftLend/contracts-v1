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
import {MockLayerZeroEndpointV2} from "../test/utils/MockLayerZeroEndpointV2.sol";
import {TestERC20} from "../test/utils/TestERC20.sol";
import {MockPriceOracle} from "../test/utils/MockPriceOracle.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {LendingPoolCollateralManager} from "src/LendingPoolCollateralManager.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";

contract LendingPoolDeployer is Script {
    string deployConfig;
    address treasury;
    address incentivesController;
    address crossL2ProverAddress;
    address currentChainWethAddress;
    address relayer;
    address poolAdmin;
    address ownerAddress;
    address lzEndpoint;
    address lzDelegate;

    struct DeployedContracts {
        address lendingPoolImpl;
        address lendingPool;
        address underlying;
        address superAsset;
        address rVaultAsset;
        address rTokenImpl;
        address variableDebtTokenImpl;
        address proxyAdmin;
        address lendingPoolAddressesProvider;
        address lendingPoolConfigurator;
        address defaultReserveInterestRateStrategy;
        address lendingRateOracle;
        address router;
        address routerImpl;
        address eventValidator;
        address lpCollateralManager;
    }

    address underlying;
    ILendingPoolAddressesProvider provider;
    address delegate;
    string name;
    string symbol;
    uint8 decimals;
    uint256 withdrawCoolDownPeriod;
    uint256 maxDepositLimit;
    uint128 lzReceiveGasLimit;
    uint128 lzComposeGasLimit;

    DeployedContracts deployedContracts;

    constructor() {
        string memory deployConfigPath = vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml"));
        deployConfig = vm.readFile(string.concat(vm.projectRoot(), deployConfigPath));
    }

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        _;
        vm.stopBroadcast();
    }

    function run() public {
        console.log("this", address(this));
        // vm.createSelectFork(vm.parseTomlString(deployConfig, ".forks.chain_c_rpc_url"));

        treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");
        incentivesController = vm.parseTomlAddress(deployConfig, ".incentives_controller.address");
        crossL2ProverAddress = vm.parseTomlAddress(deployConfig, ".forks.chain_c_cross_l2_prover_address");
        currentChainWethAddress = vm.parseTomlAddress(deployConfig, ".forks.chain_c_weth");
        relayer = vm.parseTomlAddress(deployConfig, ".relayer.address");
        poolAdmin = vm.parseTomlAddress(deployConfig, ".pool_admin.address");
        ownerAddress = vm.parseTomlAddress(deployConfig, ".owner.address");
        lzEndpoint = vm.parseTomlAddress(deployConfig, ".forks.chain_c_lz_endpoint_v2");
        lzDelegate = vm.parseTomlAddress(deployConfig, ".forks.chain_c_lz_delegate");

        deployFullLendingPool();
        outputDeploymentResult();
    }

    function deployFullLendingPool() public broadcast {
        deployedContracts.underlying = deployUnderlying();
        deployedContracts.superAsset = deploySuperAsset();
        deployedContracts.proxyAdmin = deployProxyAdmin();
        deployedContracts.lendingPoolAddressesProvider = deployLendingPoolAddressesProvider();
        deployedContracts.lendingPoolImpl = deployContract("LendingPool", ".lending_pool.salt", "");
        deployedContracts.lendingPoolConfigurator =
            deployContract("LendingPoolConfigurator", ".lending_pool_configurator.salt", "");
        deployedContracts.defaultReserveInterestRateStrategy =
            deployDefaultReserveInterestRateStrategy(deployedContracts.lendingPoolAddressesProvider);
        deployedContracts.lendingRateOracle =
            deployContractWithArgs("MockPriceOracle", ".price_oracle.salt", abi.encode(ownerAddress));

        ILendingPoolAddressesProvider lpAddressProvider =
            ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider);

        lpAddressProvider.setLendingPoolImpl(deployedContracts.lendingPoolImpl);
        LendingPool proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        deployedContracts.lendingPool = address(proxyLp);
        deployedContracts.lpCollateralManager = address(new LendingPoolCollateralManager());
        deployedContracts.eventValidator = deployEventValidator();

        (deployedContracts.router, deployedContracts.routerImpl) = deployRouter();

        deployedContracts.rVaultAsset = deployRVaultAsset();
        deployedContracts.rTokenImpl = deployContract("RToken", ".rToken.salt", "");
        vm.parseTomlString(deployConfig, ".variable_debt_token.salt");
        deployedContracts.variableDebtTokenImpl = deployContract("VariableDebtToken", ".variable_debt_token.salt", "");
        // Configure LayerZero parameters
        maxDepositLimit = 1 ether * vm.parseTomlUint(deployConfig, ".rvault_asset.max_deposit_limit");
        withdrawCoolDownPeriod = vm.parseTomlUint(deployConfig, ".rvault_asset.withdraw_cool_down_period");
        lzReceiveGasLimit = uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_receive_gas_limit"));
        lzComposeGasLimit = uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_compose_gas_limit"));
        RVaultAsset(deployedContracts.rVaultAsset).setAllLimits(lzReceiveGasLimit, lzComposeGasLimit, maxDepositLimit);

        RVaultAsset(deployedContracts.rVaultAsset).initialize(
            RVaultAssetInitializeParams(
                address(deployedContracts.superAsset),
                ILendingPoolAddressesProvider(address(deployedContracts.lendingPoolAddressesProvider)),
                lzEndpoint,
                lzDelegate,
                vm.parseTomlString(deployConfig, ".rvault_asset.name"),
                vm.parseTomlString(deployConfig, ".rvault_asset.symbol"),
                uint8(vm.parseTomlUint(deployConfig, ".underlying.decimals")),
                withdrawCoolDownPeriod,
                maxDepositLimit,
                lzReceiveGasLimit,
                lzComposeGasLimit
            )
        );

        //
        // Set critical protocol params

        lpAddressProvider.setPoolAdmin(ownerAddress);
        lpAddressProvider.setRelayer(relayer);
        lpAddressProvider.setPriceOracle(deployedContracts.lendingRateOracle);
        lpAddressProvider.setLendingPoolConfiguratorImpl(deployedContracts.lendingPoolConfigurator);
        // Configure reserve parameters
        LendingPoolConfigurator(deployedContracts.lendingPoolConfigurator).initialize(
            lpAddressProvider, deployedContracts.proxyAdmin
        );

        lpAddressProvider.setLendingPoolCollateralManager(deployedContracts.lpCollateralManager);

        LendingPoolConfigurator lendingPoolConfigurator =
            LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // Initialize core protocol components
        LendingPool(deployedContracts.lendingPoolImpl).initialize(lpAddressProvider);

        // Initialize price oracle values
        MockPriceOracle(deployedContracts.lendingRateOracle).setPrice(deployedContracts.underlying, 1 ether);

        lendingPoolConfigurator.activateReserve(deployedContracts.rVaultAsset);
        lendingPoolConfigurator.enableBorrowingOnReserve(deployedContracts.rVaultAsset);
        lendingPoolConfigurator.configureReserveAsCollateral(
            deployedContracts.rVaultAsset,
            8000, // LTV
            8000, // Liquidation threshold
            10500 // Liquidation bonus
        );

        // Link underlying asset to its rVault
        lendingPoolConfigurator.setRvaultAssetForUnderlying(deployedContracts.underlying, deployedContracts.rVaultAsset);
        configureReserves(lpAddressProvider);

        // handing over to true admins
        lpAddressProvider.setPoolAdmin(poolAdmin);
        // transfer ownership of lendingPoolAddressesProvider
        ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider).setProxyAdmin(
            deployedContracts.proxyAdmin
        );
    }

    function configureReserves(ILendingPoolAddressesProvider lpAddressProvider) internal {
        LendingPoolConfigurator proxyConfigurator =
            LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());
        // Initialize reserve with token ecosystem

        ILendingPoolConfigurator.InitReserveInput[] memory reserves = new ILendingPoolConfigurator.InitReserveInput[](1);
        reserves[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenName: vm.parseTomlString(deployConfig, ".rToken.name"),
            rTokenSymbol: vm.parseTomlString(deployConfig, ".rToken.symbol"),
            variableDebtTokenImpl: deployedContracts.variableDebtTokenImpl,
            variableDebtTokenName: vm.parseTomlString(deployConfig, ".variable_debt_token.name"),
            variableDebtTokenSymbol: vm.parseTomlString(deployConfig, ".variable_debt_token.symbol"),
            interestRateStrategyAddress: deployedContracts.defaultReserveInterestRateStrategy,
            treasury: treasury,
            incentivesController: incentivesController,
            superAsset: deployedContracts.superAsset,
            underlyingAsset: deployedContracts.rVaultAsset,
            underlyingAssetDecimals: uint8(vm.parseTomlUint(deployConfig, ".underlying.decimals")),
            underlyingAssetName: vm.parseTomlString(deployConfig, ".underlying.name"),
            params: "v1",
            salt: "initial",
            rTokenImpl: deployedContracts.rTokenImpl,
            eventValidator: deployedContracts.eventValidator
        });

        proxyConfigurator.batchInitReserve(reserves);
    }

    function _implSalt(string memory salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt));
    }

    function outputDeploymentResult() internal {
        console.log("Outputting deployment result");
        string memory obj = "result";

        vm.serializeAddress(obj, "underlying", deployedContracts.underlying);
        vm.serializeAddress(obj, "rTokenImpl", deployedContracts.rTokenImpl);
        vm.serializeAddress(obj, "variableDebtTokenImpl", deployedContracts.variableDebtTokenImpl);
        vm.serializeAddress(obj, "proxyAdmin", deployedContracts.proxyAdmin);
        vm.serializeAddress(obj, "lendingPoolAddressesProvider", deployedContracts.lendingPoolAddressesProvider);
        vm.serializeAddress(obj, "superAsset", deployedContracts.superAsset);
        vm.serializeAddress(obj, "lendingPool", deployedContracts.lendingPool);
        vm.serializeAddress(obj, "lendingPoolConfigurator", deployedContracts.lendingPoolConfigurator);
        vm.serializeAddress(
            obj, "defaultReserveInterestRateStrategy", deployedContracts.defaultReserveInterestRateStrategy
        );
        vm.serializeAddress(obj, "lendingRateOracle", deployedContracts.lendingRateOracle);
        string memory jsonOutput = vm.serializeAddress(obj, "router", deployedContracts.router);

        vm.writeJson(jsonOutput, "deployment.json");
    }

    function deployContract(string memory contractName, string memory saltKey, bytes memory constructorArgs)
        internal
        returns (address)
    {
        bytes memory creationCode = _getCreationCode(contractName);
        return _deployWithCreate2(contractName, saltKey, creationCode, constructorArgs);
    }

    function deployContractWithArgs(string memory contractName, string memory saltKey, bytes memory constructorArgs)
        internal
        returns (address)
    {
        bytes memory creationCode = _getCreationCode(contractName);
        return _deployWithCreate2(contractName, saltKey, creationCode, constructorArgs);
    }

    function _getCreationCode(string memory contractName) internal pure returns (bytes memory) {
        if (keccak256(bytes(contractName)) == keccak256(bytes("RToken"))) {
            return type(RToken).creationCode;
        }
        if (keccak256(bytes(contractName)) == keccak256(bytes("Router"))) {
            return type(Router).creationCode;
        }

        if (keccak256(bytes(contractName)) == keccak256(bytes("VariableDebtToken"))) {
            return type(VariableDebtToken).creationCode;
        }
        if (keccak256(bytes(contractName)) == keccak256(bytes("LendingPool"))) {
            return type(LendingPool).creationCode;
        }
        if (keccak256(bytes(contractName)) == keccak256(bytes("LendingPoolConfigurator"))) {
            return type(LendingPoolConfigurator).creationCode;
        }
        if (keccak256(bytes(contractName)) == keccak256(bytes("MockPriceOracle"))) {
            return type(MockPriceOracle).creationCode;
        }

        revert("Unknown contract");
    }

    function _deployWithCreate2(
        string memory contractName,
        string memory saltKey,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address) {
        string memory salt = vm.parseTomlString(deployConfig, saltKey);
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 saltBytes = _implSalt(salt);
        address preComputedAddress = vm.computeCreate2Address(saltBytes, keccak256(initCode));

        if (preComputedAddress.code.length > 0) {
            console.log("%s already deployed at %s", contractName, preComputedAddress);
            return preComputedAddress;
        }

        address addr;
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), saltBytes)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        console.log("Deployed %s at: %s", contractName, addr);
        return addr;
    }

    function deployUnderlying() internal returns (address) {
        return _deployWithCreate2(
            "TestERC20",
            ".underlying.salt",
            type(TestERC20).creationCode,
            abi.encode(
                vm.parseTomlString(deployConfig, ".underlying.name"),
                vm.parseTomlString(deployConfig, ".underlying.symbol"),
                vm.parseTomlUint(deployConfig, ".underlying.decimals")
            )
        );
    }
    //deply event validator

    function deployEventValidator() internal returns (address) {
        return _deployWithCreate2(
            "EventValidator",
            ".event_validator.salt",
            type(EventValidator).creationCode,
            abi.encode(crossL2ProverAddress)
        );
    }

    function deploySuperAsset() internal returns (address) {
        return _deployWithCreate2(
            "SuperAsset",
            ".super_token.salt",
            type(SuperAsset).creationCode,
            abi.encode(
                deployedContracts.underlying,
                vm.parseTomlString(deployConfig, ".super_token.name"),
                vm.parseTomlString(deployConfig, ".super_token.symbol"),
                currentChainWethAddress
            )
        );
    }

    function deployRVaultAsset() internal returns (address) {
        return _deployWithCreate2("RVaultAsset", ".rvault_asset.salt", type(RVaultAsset).creationCode, "");
    }

    function deployProxyAdmin() internal returns (address) {
        return _deployWithCreate2(
            "ProxyAdmin", ".proxy_admin.salt", type(ProxyAdmin).creationCode, abi.encode(ownerAddress)
        );
    }

    function deployLendingPoolAddressesProvider() internal returns (address) {
        bytes32 lpType = keccak256(bytes(vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.lpType")));

        return _deployWithCreate2(
            "LendingPoolAddressesProvider",
            ".lending_pool_addresses_provider.salt",
            type(LendingPoolAddressesProvider).creationCode,
            abi.encode(
                vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.marketId"),
                ownerAddress,
                ownerAddress,
                lpType
            )
        );
    }

    function deployDefaultReserveInterestRateStrategy(address lpAddressProvider) internal returns (address) {
        provider = ILendingPoolAddressesProvider(lpAddressProvider);

        bytes memory constructorArgs = abi.encode(
            provider,
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.optimalUtilizationRate"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.baseVariableBorrowRate"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope1"),
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope2")
        );

        return _deployWithCreate2(
            "DefaultReserveInterestRateStrategy",
            ".default_reserve_interest_rate_strategy.salt",
            type(DefaultReserveInterestRateStrategy).creationCode,
            constructorArgs
        );
    }

    function deployRouter() internal returns (address, address) {
        // Deploy implementation
        address routerImpl = deployContract("Router", ".router.salt", "");

        // Deploy proxy
        string memory salt = vm.parseTomlString(deployConfig, ".router.salt");
        bytes memory initData = abi.encodeWithSelector(
            Router.initialize.selector,
            deployedContracts.lendingPool,
            deployedContracts.lendingPoolAddressesProvider,
            deployedContracts.eventValidator
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy{salt: _implSalt(salt)}(routerImpl, deployedContracts.proxyAdmin, initData);

        console.log("Deployed Router Proxy at: %s", address(proxy));
        return (address(proxy), routerImpl);
    }
}
