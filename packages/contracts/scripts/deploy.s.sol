// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";
import {LendingRateOracle} from "../src/LendingRateOracle.sol";
import {SuperAsset} from "../src/SuperAsset.sol";
import {RToken} from "../src/tokenization/RToken.sol";
import {StableDebtToken} from "../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {L2NativeSuperchainERC20} from "../src/L2NativeSuperchainERC20.sol";
import {Router} from "../src/Router.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";
import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";

/// @dev the owner and deployer are currently the same.
/// @notice for EventValidation library change the prover address to be deployed on each chain. - https://docs.polymerlabs.org/docs/build/start/
contract LendingPoolDeployer is Script {
    string deployConfig;

    address treasury;
    address incentivesController;

    struct DeployedContracts {
        address underlying;
        address lendingPoolImpl;
        address rTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        address proxyAdmin;
        address lendingPoolAddressesProvider;
        address superAsset;
        address lendingPool;
        address lendingPoolConfigurator;
        address defaultReserveInterestRateStrategy;
        address lendingRateOracle;
        address router;
        address routerImpl;
    }

    DeployedContracts deployedContracts;

    constructor() {
        string memory deployConfigPath = vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml"));
        string memory filePath = string.concat(vm.projectRoot(), deployConfigPath);
        deployConfig = vm.readFile(filePath);
    }

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    function setUp() public {}

    function run() public {
        treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");
        incentivesController = vm.parseTomlAddress(deployConfig, ".incentives_controller.address");
        deployFullLendingPool();
        outputDeploymentResult();
    }

    function deployFullLendingPool() public broadcast {
        // Deploy contracts using CREATE2
        (address underlying) = deployL2NativeSuperchainERC20();
        (address rTokenImpl) = deployRTokenImpl();
        (address stableDebtTokenImpl) = deployStableDebtTokenImpl();
        (address variableDebtTokenImpl) = deployVariableDebtTokenImpl();
        (address proxyAdmin) = deployProxyAdmin();
        (address lpAddressProvider) = deployLendingPoolAddressesProvider(proxyAdmin);
        (address superAsset) = deploySuperAsset(lpAddressProvider, underlying);
        (address implementationLp) = deployLendingPoolImpl();
        (address lpConfigurator) = deployLendingPoolConfigurator();
        (address strategy) = deployDefaultReserveInterestRateStrategy(lpAddressProvider);
        (address oracle) = deployLendingRateOracle();

        // Set up proxy and configurator
        ILendingPoolAddressesProvider lpAddressProvider_ = ILendingPoolAddressesProvider(lpAddressProvider);
        lpAddressProvider_.setLendingPoolImpl(address(implementationLp));
        LendingPool proxyLp = LendingPool(lpAddressProvider_.getLendingPool());
        (address router, address routerImpl) = deployRouter(proxyAdmin, address(proxyLp), lpAddressProvider);
        lpAddressProvider_.setPoolAdmin(msg.sender);
        lpAddressProvider_.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        LendingPoolConfigurator proxyConfigurator =
            LendingPoolConfigurator(lpAddressProvider_.getLendingPoolConfigurator());
        lpAddressProvider_.setLendingRateOracle(address(oracle));

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenImpl: address(rTokenImpl),
            stableDebtTokenImpl: address(stableDebtTokenImpl),
            variableDebtTokenImpl: address(variableDebtTokenImpl),
            underlyingAssetDecimals: uint8(vm.parseTomlUint(deployConfig, ".token.decimals")),
            interestRateStrategyAddress: address(strategy),
            underlyingAsset: address(underlying),
            treasury: treasury,
            incentivesController: incentivesController,
            superAsset: address(superAsset),
            underlyingAssetName: vm.parseTomlString(deployConfig, ".token.name"),
            rTokenName: vm.parseTomlString(deployConfig, ".RToken1.name"),
            rTokenSymbol: vm.parseTomlString(deployConfig, ".RToken1.symbol"),
            variableDebtTokenName: vm.parseTomlString(deployConfig, ".variableDebtToken1.name"),
            variableDebtTokenSymbol: vm.parseTomlString(deployConfig, ".variableDebtToken1.symbol"),
            stableDebtTokenName: vm.parseTomlString(deployConfig, ".stableDebtToken1.name"),
            stableDebtTokenSymbol: vm.parseTomlString(deployConfig, ".stableDebtToken1.symbol"),
            params: "0x10",
            salt: _implSalt(vm.parseTomlString(deployConfig, ".deploy_config.salt"))
        });
        proxyConfigurator.batchInitReserve(input);

        deployedContracts = DeployedContracts({
            underlying: underlying,
            lendingPoolImpl: implementationLp,
            rTokenImpl: rTokenImpl,
            stableDebtTokenImpl: stableDebtTokenImpl,
            variableDebtTokenImpl: variableDebtTokenImpl,
            proxyAdmin: proxyAdmin,
            lendingPoolAddressesProvider: lpAddressProvider,
            superAsset: superAsset,
            lendingPool: address(proxyLp),
            lendingPoolConfigurator: address(proxyConfigurator),
            defaultReserveInterestRateStrategy: strategy,
            lendingRateOracle: oracle,
            router: router,
            routerImpl: routerImpl
        });
    }

    function _implSalt(string memory salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt));
    }

    function outputDeploymentResult() public {
        console.log("Outputting deployment result");

        string memory obj = "result";
        vm.serializeAddress(obj, "deployedAddress", deployedContracts.underlying);
        vm.serializeAddress(obj, "ownerAddress", vm.parseTomlAddress(deployConfig, ".token.owner_address"));

        vm.serializeAddress(obj, "RTokenAddress", deployedContracts.rTokenImpl);
        vm.serializeAddress(obj, "stableDebtTokenAddress", deployedContracts.stableDebtTokenImpl);
        vm.serializeAddress(obj, "variableDebtTokenAddress", deployedContracts.variableDebtTokenImpl);
        vm.serializeAddress(obj, "proxyAdminAddress", deployedContracts.proxyAdmin);
        vm.serializeAddress(obj, "lendingPoolAddressesProviderAddress", deployedContracts.lendingPoolAddressesProvider);
        vm.serializeAddress(obj, "superAssetAddress", deployedContracts.superAsset);
        vm.serializeAddress(obj, "lendingPoolAddress", deployedContracts.lendingPool);
        vm.serializeAddress(obj, "lendingPoolConfiguratorAddress", deployedContracts.lendingPoolConfigurator);
        vm.serializeAddress(
            obj, "defaultReserveInterestRateStrategyAddress", deployedContracts.defaultReserveInterestRateStrategy
        );
        vm.serializeAddress(obj, "lendingRateOracleAddress", deployedContracts.lendingRateOracle);
        vm.serializeAddress(obj, "routerAddress", deployedContracts.router);
        string memory jsonOutput = vm.serializeAddress(obj, "routerImplAddress", deployedContracts.routerImpl);

        vm.writeJson(jsonOutput, "deployment.json");
    }

    function deployL2NativeSuperchainERC20() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".token.salt");
        address ownerAddr_ = vm.parseTomlAddress(deployConfig, ".token.owner_address");
        string memory name = vm.parseTomlString(deployConfig, ".token.name");
        string memory symbol = vm.parseTomlString(deployConfig, ".token.symbol");
        uint256 decimals = vm.parseTomlUint(deployConfig, ".token.decimals");
        require(decimals <= type(uint8).max, "decimals exceeds uint8 range");
        bytes memory initCode = abi.encodePacked(
            type(L2NativeSuperchainERC20).creationCode, abi.encode(ownerAddr_, name, symbol, uint8(decimals))
        );
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log(
                "L2NativeSuperchainERC20 already deployed at %s", preComputedAddress, "on chain id: ", block.chainid
            );
            addr_ = preComputedAddress;
        } else {
            addr_ =
                address(new L2NativeSuperchainERC20{salt: _implSalt(salt)}(ownerAddr_, name, symbol, uint8(decimals)));
            console.log("Deployed L2NativeSuperchainERC20 at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployRTokenImpl() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".RTokenImpl.salt");
        bytes memory initCode = type(RToken).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("RToken already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new RToken{salt: _implSalt(salt)}());
            console.log("Deployed RToken Impl at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployRouter(address _proxyAdmin, address _lendingPool, address _addressesProvider)
        public
        returns (address router, address routerImpl)
    {
        string memory salt = vm.parseTomlString(deployConfig, ".router.salt");
        bytes32 bsalt = _implSalt(salt);

        // First deploy the implementation
        bytes memory initCode = type(Router).creationCode;
        address preComputedAddress = vm.computeCreate2Address(bsalt, keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("Router Impl already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            routerImpl = preComputedAddress;
        } else {
            routerImpl = address(new Router{salt: bsalt}());
            console.log("Deployed Router Impl at address: ", routerImpl, "on chain id: ", block.chainid);
        }

        // Then deploy the proxy
        bytes memory initializerData =
            abi.encodeWithSelector(Router.initialize.selector, _lendingPool, _addressesProvider);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy{salt: bsalt}(routerImpl, _proxyAdmin, initializerData);
        router = address(proxy);

        console.log("Deployed Router Proxy at address: ", router, "on chain id: ", block.chainid);
    }

    function deployLendingPoolImpl() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".lending_pool_impl.salt");
        bytes memory initCode = type(LendingPool).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("LendingPool already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new LendingPool{salt: _implSalt(salt)}());
            console.log("Deployed LendingPool at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployStableDebtTokenImpl() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".stableDebtTokenImpl.salt");
        bytes memory initCode = type(StableDebtToken).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("StableDebtToken already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new StableDebtToken{salt: _implSalt(salt)}());
            console.log("Deployed StableDebtToken at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployVariableDebtTokenImpl() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".variableDebtTokenImpl.salt");
        bytes memory initCode = type(VariableDebtToken).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("VariableDebtToken already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new VariableDebtToken{salt: _implSalt(salt)}());
            console.log("Deployed VariableDebtToken at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployLendingPoolAddressesProvider(address _proxyAdmin) public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.salt");
        address ownerAddr_ = vm.parseTomlAddress(deployConfig, ".lending_pool_addresses_provider.owner_address");
        string memory marketId_ = vm.parseTomlString(deployConfig, ".lending_pool_addresses_provider.marketId");
        bytes memory initCode = abi.encodePacked(
            type(LendingPoolAddressesProvider).creationCode, abi.encode(marketId_, ownerAddr_, _proxyAdmin)
        );
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log(
                "LendingPoolAddressesProvider already deployed at %s",
                preComputedAddress,
                "on chain id: ",
                block.chainid
            );
            addr_ = preComputedAddress;
        } else {
            // ToDo: Add lending pool deployment here
            bytes32 lendingPool = bytes32(uint256(0));
            addr_ = address(
                new LendingPoolAddressesProvider{salt: _implSalt(salt)}(marketId_, ownerAddr_, _proxyAdmin, lendingPool)
            );
            console.log("Deployed LendingPoolAddressesProvider at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deploySuperAsset(address lpAddressProvider, address underlying) public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".superchain_asset_1.salt");
        address ownerAddr_ = vm.parseTomlAddress(deployConfig, ".superchain_asset_1.owner_address");
        string memory name = vm.parseTomlString(deployConfig, ".superchain_asset_1.name");
        string memory symbol = vm.parseTomlString(deployConfig, ".superchain_asset_1.symbol");
        uint256 decimals = vm.parseTomlUint(deployConfig, ".superchain_asset_1.decimals");
        // address lzEndpoint = vm.parseTomlAddress(deployConfig, ".superchain_asset_1.lzEndpoint");
        // address lzdelegate = vm.parseTomlAddress(deployConfig, ".superchain_asset_1.lzdelegate");
        address lzEndpoint = address(0);

        require(decimals <= type(uint8).max, "decimals exceeds uint8 range");
        bytes memory initCode = abi.encodePacked(
            type(SuperAsset).creationCode,
            abi.encode(
                name, symbol, uint8(decimals), underlying, ILendingPoolAddressesProvider(lpAddressProvider), ownerAddr_
            )
        );
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("SuperAsset already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new SuperAsset{salt: _implSalt(salt)}(underlying, lzEndpoint, address(0)));
            console.log("Deployed SuperAsset at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployLendingPool() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".deploy_config.salt");
        bytes memory initCode = type(LendingPool).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("LendingPool already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new LendingPool{salt: _implSalt(salt)}());
            console.log("Deployed LendingPool at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployProxyAdmin() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".proxy_admin.salt");
        address ownerAddr_ = vm.parseTomlAddress(deployConfig, ".proxy_admin.owner_address");
        bytes memory initCode = type(ProxyAdmin).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("ProxyAdmin already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new ProxyAdmin{salt: _implSalt(salt)}(ownerAddr_));
            console.log("Deployed ProxyAdmin at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployLendingPoolConfigurator() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".lending_pool_configurator.salt");
        bytes memory initCode = type(LendingPoolConfigurator).creationCode;
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log(
                "LendingPoolConfigurator already deployed at %s", preComputedAddress, "on chain id: ", block.chainid
            );
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new LendingPoolConfigurator{salt: _implSalt(salt)}());
            console.log("Deployed LendingPoolConfigurator at address: ", addr_, "on chain id: ", block.chainid);
        }
    }

    function deployDefaultReserveInterestRateStrategy(address lpAddressProvider) public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".default_reserve_interest_rate_strategy.salt");
        uint256 optimalUtilizationRate =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.optimalUtilizationRate");
        uint256 baseVariableBorrowRate =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.baseVariableBorrowRate");
        uint256 variableRateSlope1 =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope1");
        uint256 variableRateSlope2 =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.variableRateSlope2");
        uint256 stableRateSlope1 =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.stableRateSlope1");
        uint256 stableRateSlope2 =
            vm.parseTomlUint(deployConfig, ".default_reserve_interest_rate_strategy.stableRateSlope2");
        bytes memory initCode = abi.encodePacked(
            type(DefaultReserveInterestRateStrategy).creationCode,
            abi.encode(
                ILendingPoolAddressesProvider(lpAddressProvider),
                optimalUtilizationRate,
                baseVariableBorrowRate,
                variableRateSlope1,
                variableRateSlope2,
                stableRateSlope1,
                stableRateSlope2
            )
        );
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log(
                "DefaultReserveInterestRateStrategy already deployed at %s",
                preComputedAddress,
                "on chain id: ",
                block.chainid
            );
            addr_ = preComputedAddress;
        } else {
            addr_ = address(
                new DefaultReserveInterestRateStrategy{salt: _implSalt(salt)}(
                    ILendingPoolAddressesProvider(lpAddressProvider),
                    optimalUtilizationRate,
                    baseVariableBorrowRate,
                    variableRateSlope1,
                    variableRateSlope2,
                    stableRateSlope1,
                    stableRateSlope2
                )
            );
            console.log(
                "Deployed DefaultReserveInterestRateStrategy at address: ", addr_, "on chain id: ", block.chainid
            );
        }
    }

    function deployLendingRateOracle() public returns (address addr_) {
        string memory salt = vm.parseTomlString(deployConfig, ".lending_rate_oracle.salt");
        address ownerAddr_ = vm.parseTomlAddress(deployConfig, ".lending_rate_oracle.owner_address");
        bytes memory initCode = abi.encodePacked(type(LendingRateOracle).creationCode, abi.encode(ownerAddr_));
        address preComputedAddress = vm.computeCreate2Address(_implSalt(salt), keccak256(initCode));
        if (preComputedAddress.code.length > 0) {
            console.log("LendingRateOracle already deployed at %s", preComputedAddress, "on chain id: ", block.chainid);
            addr_ = preComputedAddress;
        } else {
            addr_ = address(new LendingRateOracle{salt: _implSalt(salt)}(ownerAddr_));
            console.log("Deployed LendingRateOracle at address: ", addr_, "on chain id: ", block.chainid);
        }
    }
}
