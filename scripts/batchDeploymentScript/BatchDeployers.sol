// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

// Import all contracts from your project
import {TestERC20} from "test/utils/TestERC20.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {SuperAsset} from "src/SuperAsset.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {LendingPool} from "src/LendingPool.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {RToken} from "src/tokenization/RToken.sol";
import {VariableDebtToken} from "src/tokenization/VariableDebtToken.sol";
import {LendingPoolCollateralManager} from "src/LendingPoolCollateralManager.sol";
import {Router} from "src/Router.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {BatchDataTypes} from "./BatchDataTypes.sol";

/// @notice Batch Deployer 1 deploys contracts needed for underlying assets and pricing:
///         TestERC20, EventValidator, SuperAsset, ProxyAdmin, LendingPoolAddressesProvider,
///         DefaultReserveInterestRateStrategy, and MockPriceOracle.
contract BatchDeployer1 {
    address public underlying;
    address public eventValidator;
    address public superAsset;
    address public proxyAdmin;
    address public lendingPoolAddressesProvider;
    address public defaultReserveInterestRateStrategy;
    address public mockPriceOracle;
    // Group all deployed addresses in a struct for easier access.

    struct Addresses {
        address underlying;
        address eventValidator;
        address superAsset;
        address proxyAdmin;
        address lendingPoolAddressesProvider;
        address defaultReserveInterestRateStrategy;
        address mockPriceOracle;
    }

    constructor(BatchDataTypes.Batch1Params memory params) {
        underlying = address(
            new TestERC20(params.underlyingName, params.underlyingSymbol, params.underlyingDecimals, params.owner)
        );
        eventValidator = address(new EventValidator{salt: params.eventValidatorSalt}(params.crossL2ProverAddress));
        superAsset = address(
            new SuperAsset{salt: params.superAssetSalt}(
                underlying, params.superAssetName, params.superAssetSymbol, params.currentChainWethAddress
            )
        );
        proxyAdmin = address(new ProxyAdmin(params.ownerAddress));
        lendingPoolAddressesProvider = address(
            new LendingPoolAddressesProvider{salt: params.lpAddressProviderSalt}(
                params.marketId, params.ownerAddress, params.ownerAddress, params.lpType
            )
        );
        defaultReserveInterestRateStrategy = address(
            new DefaultReserveInterestRateStrategy(
                ILendingPoolAddressesProvider(lendingPoolAddressesProvider),
                params.optimalUtilizationRate,
                params.baseVariableBorrowRate,
                params.variableRateSlope1,
                params.variableRateSlope2
            )
        );
        mockPriceOracle = address(new MockPriceOracle{salt: params.oracleSalt}(params.ownerAddress));
    }

    // Return all deployed addresses as one struct.
    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({
            underlying: underlying,
            eventValidator: eventValidator,
            superAsset: superAsset,
            proxyAdmin: proxyAdmin,
            lendingPoolAddressesProvider: lendingPoolAddressesProvider,
            defaultReserveInterestRateStrategy: defaultReserveInterestRateStrategy,
            mockPriceOracle: mockPriceOracle
        });
    }
}

/// @notice Batch Deployer 2 deploys the core lending pool implementation and its configurator.

contract BatchDeployer2 {
    address public lendingPoolImpl;
    address public lendingPoolConfigurator;

    constructor(bytes32 lpSalt, bytes32 lpConfiguratorSalt) {
        lendingPoolImpl = address(new LendingPool{salt: lpSalt}());
        lendingPoolConfigurator = address(new LendingPoolConfigurator{salt: lpConfiguratorSalt}());
    }

    struct Addresses {
        address lendingPoolImpl;
        address lendingPoolConfigurator;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({lendingPoolImpl: lendingPoolImpl, lendingPoolConfigurator: lendingPoolConfigurator});
    }
}
/// @notice Batch Deployer 3 deploys the tokenization contracts: RVaultAsset, RToken, and VariableDebtToken.

contract BatchDeployer3 {
    address public rVaultAsset;
    address public rToken;
    address public variableDebtToken;

    constructor(bytes32 rVaultAssetSalt, bytes32 rTokenSalt, bytes32 variableDebtTokenSalt) {
        rVaultAsset = address(new RVaultAsset{salt: rVaultAssetSalt}());
        rToken = address(new RToken{salt: rTokenSalt}());
        variableDebtToken = address(new VariableDebtToken{salt: variableDebtTokenSalt}());
    }

    struct Addresses {
        address rVaultAsset;
        address rToken;
        address variableDebtToken;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({rVaultAsset: rVaultAsset, rToken: rToken, variableDebtToken: variableDebtToken});
    }
}

/// @notice Batch Deployer 4 deploys the collateral manager and the Router (with proxy).
///         The Router’s proxy initialization requires addresses deployed in other batches.
///         Pass in lendingPool, lendingPoolAddressesProvider, eventValidator, and proxyAdmin.
contract BatchDeployer4 {
    address public lendingPoolCollateralManager;
    address public router;

    constructor(bytes32 routerSalt) {
        lendingPoolCollateralManager = address(new LendingPoolCollateralManager());
        router = address(new Router{salt: routerSalt}());
    }

    struct Addresses {
        address lendingPoolCollateralManager;
        address router;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({lendingPoolCollateralManager: lendingPoolCollateralManager, router: router});
    }
}
