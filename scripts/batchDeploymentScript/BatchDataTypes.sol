// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";

import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {BatchDeployer1, BatchDeployer2, BatchDeployer3, BatchDeployer4} from "./BatchDeployers.sol";
import {LendingPool} from "src/LendingPool.sol";

library BatchDataTypes {
    struct Batch1Params {
        string underlyingName;
        string underlyingSymbol;
        uint8 underlyingDecimals;
        address crossL2ProverAddress;
        string superAssetName;
        string superAssetSymbol;
        address currentChainWethAddress;
        address ownerAddress;
        string marketId;
        bytes32 lpType;
        uint256 optimalUtilizationRate;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
        bytes32 superAssetSalt;
        bytes32 eventValidatorSalt;
        bytes32 lpAddressProviderSalt;
        bytes32 oracleSalt;
        address owner;
    }

    /* ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ MainDeployerLocalVars Struct ┃
    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ */

    struct MainDeployerLocalVars {
        address crossL2ProverAddress;
        address currentChainWethAddress;
        address poolAdmin;
        address ownerAddress;
        uint8 underlyingDecimals;
        bytes32 lpType;
        ILendingPoolAddressesProvider lpProvider;
        LendingPoolConfigurator proxyConfigurator;
        LendingPool proxyLp;
    }

    /* ╔══════════════════════════════╗
    ║       Batch1Addresses        ║  // (Underlying Assets, Oracle, Proxy)
    ╚══════════════════════════════╝ */

    struct Batch1Addresses {
        address underlying;
        address eventValidator;
        address superAsset;
        address proxyAdmin;
        address lendingPoolAddressesProvider;
        address defaultReserveInterestRateStrategy;
        address mockPriceOracle;
    }

    // ╔══════════════════════════════╗
    // ║       Batch2Addresses        ║  // (LendingPool, Configurator)
    // ╚══════════════════════════════╝
    struct Batch2Addresses {
        address lendingPoolImpl;
        address lendingPoolConfigurator;
    }

    // ╔══════════════════════════════╗
    // ║       Batch3Addresses        ║  // (Tokenization Contracts)
    // ╚══════════════════════════════╝
    struct Batch3Addresses {
        address rVaultAsset;
        address rToken;
        address variableDebtToken;
    }

    // ╔══════════════════════════════╗
    // ║       Batch4Addresses        ║  // (Collateral Manager & Router)
    // ╚══════════════════════════════╝
    struct Batch4Addresses {
        address lendingPoolCollateralManager;
        address routerImpl;
        address proxyRouter;
    }

    // ╔══════════════════════════════╗
    // ║       BatchDeployerSet       ║  (All Batch Deployers)
    // ╚══════════════════════════════╝
    struct BatchDeployerSet {
        BatchDeployer1 bd1;
        BatchDeployer2 bd2;
        BatchDeployer3 bd3;
        BatchDeployer4 bd4;
    }

    // ╔══════════════════════════════╗
    // ║      BatchAddressesSet       ║  (All Deployed Addresses)
    // ╚══════════════════════════════╝
    struct BatchAddressesSet {
        Batch1Addresses batch1Addrs;
        Batch2Addresses batch2Addrs;
        Batch3Addresses batch3Addrs;
        Batch4Addresses batch4Addrs;
    }
}
