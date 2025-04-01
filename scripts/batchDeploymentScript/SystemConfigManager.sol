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
import {SuperAsset} from "src/SuperAsset.sol";
import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
import {TestERC20} from "test/utils/TestERC20.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {console} from "forge-std/Script.sol";

contract SystemConfigManager is Initializable {
    address owner;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Constructor                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address _owner) {
        owner = _owner;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Initializer                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(
        BatchDataTypes.MainDeployerLocalVars calldata vars,
        BatchDataTypes.BatchAddressesSet calldata batchAddressesSet,
        ILendingPoolConfigurator.InitReserveInput[] calldata reserveInputs,
        BatchDataTypes.DefaultStrategyInitParams memory strategyParams,
        BatchDataTypes.UnderlyingInitParams memory underlyingInitParams,
        RVaultAssetInitializeParams calldata rVaultAssetInitializeParams,
        BatchDataTypes.SuperAssetInitParams memory superAssetInitParams
    ) external initializer returns (address proxyRouter) {
        console.log(owner);
        console.log(msg.sender);

        require(owner == msg.sender, "OnlyOwner");

        require(vars.ownerAddress != address(0), "Owner address cannot be zero");

        // Initialize Basic Contract's params

        DefaultReserveInterestRateStrategy(batchAddressesSet.batch1Addrs.defaultReserveInterestRateStrategy).initialize(
            strategyParams.lendingPoolAddressesProvider,
            strategyParams.optimalUtilizationRate,
            strategyParams.baseVariableBorrowRate,
            strategyParams.variableRateSlope1,
            strategyParams.variableRateSlope2
        );
        TestERC20(payable(batchAddressesSet.batch1Addrs.underlying)).initialize(
            underlyingInitParams.name,
            underlyingInitParams.symbol,
            underlyingInitParams.decimals,
            underlyingInitParams.owner
        );
        SuperAsset(payable(batchAddressesSet.batch1Addrs.superAsset)).initialize(
            superAssetInitParams.underlying,
            superAssetInitParams.name,
            superAssetInitParams.symbol,
            superAssetInitParams.weth
        );

        // Set core protocol parameters.
        vars.lpProvider.setPoolAdmin(address(this));
        vars.lpProvider.setLendingPoolImpl(batchAddressesSet.batch2Addrs.lendingPoolImpl);
        for (uint256 i = 0; i < vars.relayers.length; i++) {
            address relayer = vars.relayers[i];
            vars.lpProvider.setRelayerStatus(relayer, true);
        }

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
        
        EventValidator(batchAddressesSet.batch1Addrs.eventValidator).initialize(vars.crossL2ProverAddress,proxyRouter,proxyLp);
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
