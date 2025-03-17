/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    License and Version                         */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    Protocol Imports                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";
import {ICrossL2Prover} from "../src/interfaces/ICrossL2Prover.sol";
import {ISuperAsset} from "../src/interfaces/ISuperAsset.sol";
import {IAaveIncentivesController} from "../src/interfaces/IAaveIncentivesController.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";
import {IRVaultAsset, RVaultAssetInitializeParams} from "../src/interfaces/IRVaultAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    Testing Imports                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {TestERC20} from "./utils/TestERC20.sol";
import {MockPriceOracle} from "./utils/MockPriceOracle.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    Core Contract Imports                     */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
import {IncentivesController} from "./utils/IncentivesController.sol";
import {SuperAsset} from "../src/SuperAsset.sol";
import {RToken} from "../src/tokenization/RToken.sol";
import {RVaultAsset} from "../src/RVaultAsset.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Router} from "../src/Router.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {DataTypes} from "../src/libraries/types/DataTypes.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    LayerZero Imports                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
import {MessagingFee, MessagingReceipt} from "../src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {SendParam, OFTReceipt} from "../src/libraries/helpers/layerzero/IOFT.sol";
import {OFT} from "../src/libraries/helpers/layerzero/OFT.sol";
import {EndpointV2} from "../src/libraries/helpers/layerzero/EndpointV2.sol";
import {
    IOAppOptionsType3, EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {OFTMsgCodec} from "src/libraries/helpers/layerzero/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {LendingPoolCollateralManager} from "src/LendingPoolCollateralManager.sol";

contract Base is TestHelperOz5 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Structs Definition                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct ChainDetails {
        uint256 forkId;
        uint256 chainId;
        address endpoint;
        address weth;
        address crossL2Prover;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address testToken;
    ChainDetails[2] supportedChains;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Test Addresses                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address owner = makeAddr("owner");
    address poolAdmin1 = makeAddr("poolAdmin1");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address liquidityProvider = makeAddr("liquidityProvider");
    address liquidator = makeAddr("liquidator");
    address bootStrapper = makeAddr("bootStrapper");

    address relayer = makeAddr("relayer");
    address emergencyAdmin = makeAddr("emergencyAdmin");
    address alice = makeAddr("alice");
    address _delegate = makeAddr("_delegate");

    uint256 constant INITIAL_BALANCE = 10000 ether;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Contract Variables                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address incentivesController;
    address treasury;
    address proxyAdmin;
    address strategy;
    address rVaultAsset1;
    address rVaultAsset2;
    MockPriceOracle oracle1;
    MockPriceOracle oracle2;
    RToken rToken;
    LendingPoolCollateralManager lpCollateralManager;
    VariableDebtToken variableDebtTokenImpl;

    LendingPool proxyLp;
    LendingPool implementationLp1;
    LendingPool implementationLp2;

    SuperAsset superAsset;
    SuperAsset superAssetWeth;
    TestERC20 INR;
    TestERC20 underlyingAsset;
    LendingPoolConfigurator lpConfigurator;
    LendingPoolConfigurator proxyConfigurator;
    LendingPoolAddressesProvider lpAddressProvider1;
    LendingPoolAddressesProvider lpAddressProvider2;
    EndpointV2 lzEndpoint;
    Router router;
    EventValidator eventValidator;
    string filePath;
    string deployConfig;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Token Configuration                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    string public constant underlyingAssetName = "TUSDC";
    string public constant underlyingAssetSymbol = "USDC";
    string public constant rTokenName1 = "rTUSDC1";
    string public constant rTokenSymbol1 = "rTUSDC1";
    string public constant rVaultAssetTokenName1 = "rVaultAsset-TUSDC1";
    string public constant rVaultAssetTokenSymbol1 = "rVaultAsset-rTUSDC1";
    string public constant rVaultAssetTokenName2 = "rVaultAsset-TUSDC2";
    string public constant rVaultAssetTokenSymbol2 = "rVaultAsset-rTUSDC2";
    string public constant rTokenName2 = "rTUSDC2";
    string public constant rTokenSymbol2 = "rTUSDC2";
    string public constant superAssetTokenName = "superTUSDC";
    string public constant superAsseTokenSymbol = "superTUSDC";
    string public constant variableDebtTokenName = "vDebt-TUSDC";
    string public constant variableDebtTokenSymbol = "vDBT-rTUSDC";
    uint8 underlyingAssetDecimals = 6;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Setup Function                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setUp() public virtual override {
        super.setUp();
        // ############## Load deploy config ##############
        filePath =
            string.concat(vm.projectRoot(), vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml")));
        deployConfig = vm.readFile(filePath);
        // uint256 forkId;
        // uint256 chainId;
        // address endpoint;
        // address weth;
        // address crossL2Prover;

        // ############## Read deploy config variables ##############
        supportedChains[0].forkId = vm.createFork(vm.parseTomlString(deployConfig, ".forks.chain_a_rpc_url"));
        supportedChains[0].crossL2Prover = vm.parseTomlAddress(deployConfig, ".forks.chain_a_cross_l2_prover_address");
        supportedChains[0].weth = vm.parseTomlAddress(deployConfig, ".forks.chain_a_weth");
        supportedChains[0].endpoint = vm.parseTomlAddress(deployConfig, ".forks.chain_a_lz_endpoint_v2");
        supportedChains[0].chainId = vm.parseTomlUint(deployConfig, ".forks.chain_a_chain_id");

        supportedChains[1].forkId = vm.createFork(vm.parseTomlString(deployConfig, ".forks.chain_b_rpc_url"));
        supportedChains[1].crossL2Prover = vm.parseTomlAddress(deployConfig, ".forks.chain_b_cross_l2_prover_address");
        supportedChains[1].weth = vm.parseTomlAddress(deployConfig, ".forks.chain_b_weth");
        supportedChains[1].endpoint = vm.parseTomlAddress(deployConfig, ".forks.chain_b_lz_endpoint_v2");
        supportedChains[1].chainId = vm.parseTomlUint(deployConfig, ".forks.chain_b_chain_id");

        treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");

        // ############## Create Fork to test ##############
        vm.selectFork(supportedChains[0].forkId);

        // ################ Deploy Components ################
        vm.prank(owner);
        eventValidator = new EventValidator(owner);
        vm.prank(owner);
        eventValidator.initialize(supportedChains[0].crossL2Prover);

        vm.prank(owner);
        proxyAdmin = address(new ProxyAdmin{salt: "proxyAdmin"}(owner));
        vm.label(proxyAdmin, "proxyAdmin");

        // ################ Deploy UnderlyingAsset ################
        vm.prank(owner);
        underlyingAsset = new TestERC20(owner);
        vm.prank(owner);
        underlyingAsset.initialize(underlyingAssetName, underlyingAssetSymbol, underlyingAssetDecimals, owner);
        vm.label(address(underlyingAsset), "underlyingAsset");

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              LendingPool Configuration                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        // Deploy LendingPoolAddressesProvider
        lpAddressProvider1 =
            new LendingPoolAddressesProvider("TUSDC", owner, proxyAdmin, keccak256("OpSuperchain_LENDING_POOL"));
        lpAddressProvider2 = new LendingPoolAddressesProvider("TUSDC", owner, proxyAdmin, keccak256("ARB_LENDING_POOL"));

        vm.label(address(lpAddressProvider1), "lpAddressProvider1");
        vm.label(address(lpAddressProvider2), "lpAddressProvider2");

        // Deploy LendingPool Implementation
        vm.prank(owner);
        implementationLp1 = new LendingPool();
        vm.label(address(implementationLp1), "implementationLp1");

        vm.prank(owner);
        implementationLp2 = new LendingPool();
        vm.label(address(implementationLp2), "implementationLp2");

        // Set LendingPool Implementation
        vm.prank(owner);
        lpAddressProvider1.setLendingPoolImpl(address(implementationLp1));
        vm.prank(owner);
        lpAddressProvider2.setLendingPoolImpl(address(implementationLp2));
        proxyLp = LendingPool(lpAddressProvider1.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              Router and Oracle Setup                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        // Deploy Router
        vm.prank(owner);
        router = new Router{salt: "router"}();
        vm.prank(owner);
        router.initialize(address(proxyLp), address(lpAddressProvider1), address(eventValidator));
        vm.deal(address(router), 100 ether);

        vm.label(address(lpAddressProvider1), "lpAddressProvider1");
        vm.label(address(lpAddressProvider2), "lpAddressProvider2");

        // Deploy Oracle
        vm.prank(owner);
        oracle1 = new MockPriceOracle(owner);
        vm.prank(owner);
        oracle2 = new MockPriceOracle(owner);

        // Setup LayerZero Endpoint
        lzEndpoint = EndpointV2(supportedChains[0].endpoint);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              Asset Deployment                               */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        // Deploy SuperAsset
        vm.prank(owner);
        superAsset = new SuperAsset(owner);
        vm.prank(owner);
        superAsset.initialize(
            address(underlyingAsset), superAssetTokenName, superAsseTokenSymbol, supportedChains[0].weth
        );

        vm.prank(owner);
        superAssetWeth = new SuperAsset(owner);
        vm.prank(owner);
        superAssetWeth.initialize(
            address(supportedChains[0].weth), superAssetTokenName, superAsseTokenSymbol, supportedChains[0].weth
        );
        vm.label(address(superAsset), "superAsset");
        vm.label(address(superAssetWeth), "superAssetWeth");

        // Deploy RVaultAsset
        console.log("Deploying RVaultAsset");
        uint32[] memory lzEids;
        uint256[] memory lzEidChains;

        vm.startPrank(owner);
        rVaultAsset1 = address(new RVaultAsset{salt: "rVaultAsset1Impl"}(owner));
        IRVaultAsset(rVaultAsset1).initialize(
            RVaultAssetInitializeParams(
                address(superAsset),
                ILendingPoolAddressesProvider(address(lpAddressProvider1)),
                address(lzEndpoint),
                _delegate,
                rVaultAssetTokenName1,
                rVaultAssetTokenSymbol1,
                underlyingAssetDecimals,
                vm.parseTomlUint(deployConfig, ".rvault_asset.withdraw_cool_down_period"),
                1 ether * vm.parseTomlUint(deployConfig, ".rvault_asset.max_deposit_limit"),
                uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_receive_gas_limit")),
                uint128(vm.parseTomlUint(deployConfig, ".layerzero.lz_compose_gas_limit")),
                vm.parseTomlAddress(deployConfig, ".owner.address"),
                lzEidChains,
                lzEids
            )
        );

        rVaultAsset2 = address(new RVaultAsset{salt: "rVaultAsset2Impl"}(owner));
        IRVaultAsset(rVaultAsset2).initialize(
            RVaultAssetInitializeParams(
                address(underlyingAsset),
                ILendingPoolAddressesProvider(address(lpAddressProvider2)),
                address(lzEndpoint),
                _delegate,
                rVaultAssetTokenName2,
                rVaultAssetTokenSymbol2,
                underlyingAssetDecimals,
                1 days,
                1000 ether,
                200000,
                500000,
                owner,
                lzEidChains,
                lzEids
            )
        );
        vm.stopPrank();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              Token Setup and Configuration                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        // Deploy Incentives Controller
        vm.prank(owner);
        incentivesController = address(new IncentivesController{salt: "incentivesController"}());

        // Deploy and Initialize RToken
        vm.prank(owner);
        rToken = new RToken{salt: "rToken"}();

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              Pool Configuration                             */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        lpCollateralManager = new LendingPoolCollateralManager();

        // Set Addresses in LpAddressesProvider
        vm.startPrank(owner);
        lpAddressProvider1.setPoolAdmin(poolAdmin1);
        lpAddressProvider1.setRelayerStatus(relayer, true);
        lpAddressProvider1.setRouter(address(router));
        lpAddressProvider1.setLendingPoolCollateralManager(address(lpCollateralManager));

        lpAddressProvider2.setPoolAdmin(poolAdmin1);
        lpAddressProvider2.setRelayerStatus(relayer, true);
        lpAddressProvider2.setRouter(address(router));
        lpAddressProvider2.setLendingPoolCollateralManager(address(lpCollateralManager));
        lpAddressProvider1.setPriceOracle(address(oracle1));
        lpAddressProvider2.setPriceOracle(address(oracle2));
        oracle1.setPrice(address(underlyingAsset), 1 ether);
        oracle1.setPrice(address(rVaultAsset1), 1 ether);

        oracle2.setPrice(address(underlyingAsset), 1 ether);
        oracle2.setPrice(address(rVaultAsset1), 1 ether);

        vm.stopPrank();

        // Deploy VariableDebtToken
        vm.prank(owner);
        variableDebtTokenImpl = new VariableDebtToken{salt: "variableDebtTokenImpl"}();

        // Deploy and Configure LendingPoolConfigurator
        vm.prank(owner);
        lpConfigurator = new LendingPoolConfigurator();
        vm.prank(owner);
        lpConfigurator.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider1)), proxyAdmin);

        vm.prank(owner);
        lpAddressProvider1.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider1.getLendingPoolConfigurator());

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*              Reserve Configuration                          */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        // Activate and Configure Reserve
        vm.startPrank(poolAdmin1);
        proxyConfigurator.activateReserve(address(rVaultAsset1));
        proxyConfigurator.enableBorrowingOnReserve(address(rVaultAsset1));
        proxyConfigurator.configureReserveAsCollateral(address(rVaultAsset1), 8000, 8000, 10500);
        vm.stopPrank();

        // Deploy Interest Rate Strategy
        vm.prank(owner);
        strategy = address(new DefaultReserveInterestRateStrategy(owner));
        vm.prank(owner);
        DefaultReserveInterestRateStrategy(strategy).initialize(
            ILendingPoolAddressesProvider(address(lpAddressProvider1)),
            0.8 * 1e27, // optimalUtilizationRate
            0.02 * 1e27, // baseVariableBorrowRate
            0.04 * 1e27, // variableRateSlope1
            0.75 * 1e27 // variableRateSlope2
        );
        vm.label(strategy, "DefaultReserveInterestRateStrategy");

        // Set RVaultAsset for Underlying
        vm.prank(poolAdmin1);
        proxyConfigurator.setRvaultAssetForUnderlying(address(underlyingAsset), address(rVaultAsset1));

        // Initialize Reserve
        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenName: rTokenName1,
            rTokenSymbol: rTokenSymbol1,
            variableDebtTokenImpl: address(variableDebtTokenImpl),
            variableDebtTokenName: variableDebtTokenName,
            variableDebtTokenSymbol: variableDebtTokenSymbol,
            interestRateStrategyAddress: strategy,
            treasury: treasury,
            incentivesController: incentivesController,
            superAsset: address(superAsset),
            underlyingAsset: address(rVaultAsset1),
            underlyingAssetDecimals: underlyingAssetDecimals,
            underlyingAssetName: underlyingAssetName,
            params: "v",
            salt: "salt",
            rTokenImpl: address(rToken),
            eventValidator: address(eventValidator)
        });

        vm.prank(poolAdmin1);
        proxyConfigurator.batchInitReserve(input);
    }
}
