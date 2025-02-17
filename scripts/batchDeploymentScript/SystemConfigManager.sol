// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {LendingPool} from "src/LendingPool.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";
import {BatchDataTypes} from "./BatchDataTypes.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Router} from "src/Router.sol";
import {console} from "forge-std/Script.sol";

contract SystemConfigManager is Initializable {
    function initialize(
        BatchDataTypes.MainDeployerLocalVars calldata vars,
        BatchDataTypes.BatchAddressesSet calldata batchAddressesSet,
        ILendingPoolConfigurator.InitReserveInput[] calldata reserveInputs,
        RVaultAssetInitializeParams calldata rVaultAssetInitializeParams,
        address relayer
    ) external initializer returns (address proxyRouter) {
        require(vars.ownerAddress != address(0), "Owner address cannot be zero");

        // Set core protocol parameters.
        vars.lpProvider.setPoolAdmin(address(this));
        vars.lpProvider.setLendingPoolImpl(batchAddressesSet.batch2Addrs.lendingPoolImpl);
        vars.lpProvider.setRelayer(relayer);

        vars.lpProvider.setLendingPoolCollateralManager(
            address(batchAddressesSet.batch4Addrs.lendingPoolCollateralManager)
        );
        vars.lpProvider.setPriceOracle(batchAddressesSet.batch1Addrs.mockPriceOracle);
        vars.lpProvider.setLendingPoolConfiguratorImpl(batchAddressesSet.batch2Addrs.lendingPoolConfigurator);
        // Initialize the LendingPoolConfigurator.
        LendingPoolConfigurator(batchAddressesSet.batch2Addrs.lendingPoolConfigurator).initialize(
            vars.lpProvider, batchAddressesSet.batch1Addrs.proxyAdmin
        );

        LendingPoolConfigurator proxyConfigurator =
            LendingPoolConfigurator(vars.lpProvider.getLendingPoolConfigurator());

        // Init Router
        address proxyLp = address(LendingPool(ILendingPoolAddressesProvider(vars.lpProvider).getLendingPool()));

        bytes memory initData = abi.encodeWithSelector(
            Router.initialize.selector, proxyLp, address(vars.lpProvider), batchAddressesSet.batch1Addrs.eventValidator
        );
        proxyRouter = address(
            new TransparentUpgradeableProxy(
                batchAddressesSet.batch4Addrs.routerImpl, batchAddressesSet.batch1Addrs.proxyAdmin, initData
            )
        );

        vars.lpProvider.setRouter(proxyRouter);

        // Initialize the LendingPool.
        LendingPool(batchAddressesSet.batch2Addrs.lendingPoolImpl).initialize(vars.lpProvider);

        // Configure the reserve for RVaultAsset.
        proxyConfigurator.activateReserve(batchAddressesSet.batch3Addrs.rVaultAsset);
        proxyConfigurator.enableBorrowingOnReserve(batchAddressesSet.batch3Addrs.rVaultAsset);
        proxyConfigurator.configureReserveAsCollateral(
            batchAddressesSet.batch3Addrs.rVaultAsset,
            8000, // Loan-to-value (LTV)
            8000, // Liquidation threshold
            10500 // Liquidation bonus
        );

        // Initialize RVaultAsset.
        RVaultAsset(payable(batchAddressesSet.batch3Addrs.rVaultAsset)).initialize(rVaultAssetInitializeParams);

        proxyConfigurator.setRvaultAssetForUnderlying(
            batchAddressesSet.batch1Addrs.underlying, batchAddressesSet.batch3Addrs.rVaultAsset
        );

        // Set an initial price in the price oracle.
        MockPriceOracle(batchAddressesSet.batch1Addrs.mockPriceOracle).setPrice(
            batchAddressesSet.batch1Addrs.underlying, 1 ether
        );

        // initialize reserves
        proxyConfigurator.batchInitReserve(reserveInputs);

        // Update pool admin and proxy admin.
        vars.lpProvider.setPoolAdmin(vars.poolAdmin);
        vars.lpProvider.setProxyAdmin(batchAddressesSet.batch1Addrs.proxyAdmin);
        vars.lpProvider.transferOwnership(vars.ownerAddress);
    }
}
