import {Initializable} from "@solady/utils/Initializable.sol";
import {console} from "forge-std/Script.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {LendingPool} from "src/LendingPool.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";
import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";
import {BatchDataTypes} from "./BatchDataTypes.sol";

contract SystemConfigManager is Initializable {
    function initialize(
        BatchDataTypes.MainDeployerLocalVars calldata vars,
        BatchDataTypes.BatchAddressesSet calldata batchAddressesSet,
        ILendingPoolConfigurator.InitReserveInput[] calldata reserveInputs,
        RVaultAssetInitializeParams calldata rVaultAssetInitializeParams,
        address relayer
    ) external initializer {
        require(vars.ownerAddress != address(0), "Owner address cannot be zero");

        // Set core protocol parameters.
        vars.lpProvider.setPoolAdmin(address(this));
        vars.lpProvider.setLendingPoolImpl(batchAddressesSet.batch2Addrs.lendingPoolImpl);
        vars.lpProvider.setRelayer(relayer);
        vars.lpProvider.setPriceOracle(batchAddressesSet.batch1Addrs.mockPriceOracle);
        vars.lpProvider.setLendingPoolConfiguratorImpl(batchAddressesSet.batch2Addrs.lendingPoolConfigurator);
        LendingPoolConfigurator proxyConfigurator =
            LendingPoolConfigurator(vars.lpProvider.getLendingPoolConfigurator());

        // Initialize the LendingPool.
        LendingPool(batchAddressesSet.batch2Addrs.lendingPoolImpl).initialize(vars.lpProvider);
        // Initialize the LendingPoolConfigurator.
        LendingPoolConfigurator(batchAddressesSet.batch2Addrs.lendingPoolConfigurator).initialize(
            vars.lpProvider, batchAddressesSet.batch1Addrs.proxyAdmin
        );

        // Set the LendingPoolCollateralManager.
        vars.lpProvider.setLendingPoolCollateralManager(batchAddressesSet.batch4Addrs.lendingPoolCollateralManager);

        // Configure the reserve for RVaultAsset.
        proxyConfigurator.activateReserve(batchAddressesSet.batch3Addrs.rVaultAsset);
        proxyConfigurator.enableBorrowingOnReserve(batchAddressesSet.batch3Addrs.rVaultAsset);
        proxyConfigurator.configureReserveAsCollateral(
            batchAddressesSet.batch3Addrs.rVaultAsset,
            8000, // Loan-to-value (LTV)
            8000, // Liquidation threshold
            10500 // Liquidation bonus
        );
        proxyConfigurator.setRvaultAssetForUnderlying(
            batchAddressesSet.batch1Addrs.testERC20, batchAddressesSet.batch3Addrs.rVaultAsset
        );

        // Set an initial price in the price oracle.
        MockPriceOracle(batchAddressesSet.batch1Addrs.mockPriceOracle).setPrice(
            batchAddressesSet.batch1Addrs.testERC20, 1 ether
        );

        // Initialize RVaultAsset.
        RVaultAsset(batchAddressesSet.batch3Addrs.rVaultAsset).initialize(rVaultAssetInitializeParams);
        // initialize reserves
        proxyConfigurator.batchInitReserve(reserveInputs);

        // Update pool admin and proxy admin.
        vars.lpProvider.setPoolAdmin(vars.poolAdmin);
        vars.lpProvider.setProxyAdmin(batchAddressesSet.batch1Addrs.proxyAdmin);
        vars.lpProvider.transferOwnership(vars.ownerAddress);
    }
}
