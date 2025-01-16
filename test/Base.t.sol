// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";
import {ICrossL2Prover} from "../src/interfaces/ICrossL2Prover.sol";
import {ISuperAsset} from "../src/interfaces/ISuperAsset.sol";
import {IAaveIncentivesController} from "../src/interfaces/IAaveIncentivesController.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";
import {IRVaultAsset} from "../src/interfaces/IRVaultAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IncentivesController} from "./utils/IncentivesController.sol";
import {MessagingFee, MessagingReceipt} from "../src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {SendParam, OFTReceipt} from "../src/libraries/helpers/layerzero/IOFT.sol";

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {TestERC20} from "./utils/TestERC20.sol";
import {SuperAsset} from "../src/SuperAsset.sol";
import {RToken} from "../src/tokenization/RToken.sol";
import {RVaultAsset} from "../src/RVaultAsset.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {OFT} from "../src/libraries/helpers/layerzero/OFT.sol";

import {EndpointV2} from "../src/libraries/helpers/layerzero/EndpointV2.sol";
import {Router} from "../src/Router.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {DataTypes} from "../src/libraries/types/DataTypes.sol";

// OApp imports
import {
    IOAppOptionsType3, EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports/
import {OFTMsgCodec} from "src/libraries/helpers/layerzero/OFTMsgCodec.sol";

import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";

contract Base is TestHelperOz5 {
    //////////////////////////
    //// Structs Helpers /////
    /////////////////////////

    struct temps {
        address owner;
        address emergencyAdmin;
        address proxyAdmin;
        address poolAdmin;
        address lendingPoolConfigurator;
        address lendingPoolAddressesProvider;
        mapping(address underlyingAsset => Market) markets;
    }

    struct Market {
        uint256 marketId;
        address underlyingAsset;
        address rTokenImpl;
        address variableDebtTokenImpl;
        address SuperAsset;
        address aToken;
        address variableDebtToken;
        address interestRateStrategy;
        address treasury;
        address incentivesController;
    }

    //////////////////////////
    ///// State variables ////
    /////////////////////////
    address testToken;
    mapping(uint256 chainId => temps) public config;

    ///////////////////////////
    ///// Utility Addressse ///
    ///////////////////////////

    address owner = makeAddr("owner");
    address poolAdmin1 = makeAddr("poolAdmin1");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address liquidityProvider = makeAddr("liquidityProvider");

    address relayer = makeAddr("relayer");
    address emergencyAdmin = makeAddr("emergencyAdmin");
    address alice = makeAddr("alice");
    address _delegate = makeAddr("_delegate");

    //////////////////////////////
    //// Placeholder Addresses ///
    //////////////////////////////

    address incentivesController;
    address treasury;
    LendingPool proxyLp;
    LendingPool implementationLp;

    SuperAsset superAsset;
    SuperAsset superAssetWeth;

    address proxyAdmin;
    TestERC20 INR;
    TestERC20 underlyingAsset;
    LendingPoolConfigurator lpConfigurator;
    LendingPoolConfigurator proxyConfigurator;
    LendingPoolAddressesProvider lpAddressProvider1;
    LendingPoolAddressesProvider lpAddressProvider2;

    EndpointV2 lzEndpoint;
    Router router;
    address rVaultAsset1;
    address rVaultAsset2;
    address chain_b_current_wethAddress;
    EventValidator eventValidator;
    address strategy;

    struct ChainInfo{
        uint256 forkId;
        uint256 chainId;
    }
    ChainInfo[] supportedChains = new ChainInfo[](2);

    //  ######## Token metadata ########
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

    function setUp() public virtual override {

        super.setUp();
        // vm.chainId(1);
        // ############## Load deploy config ##############
        string memory deployConfigPath = vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml"));
        string memory filePath = string.concat(vm.projectRoot(), deployConfigPath);
        string memory deployConfig = vm.readFile(filePath);

        // ############## Read deploy config variables ##############
        string memory chain_a_rpc = vm.parseTomlString(deployConfig, ".forks.chain_a_rpc_url");
        address chain_a_cross_l2_prover_address =vm.parseTomlAddress(deployConfig, ".forks.chain_a_cross_l2_prover_address");
        address chain_a_current_wethAddress = vm.parseTomlAddress(deployConfig, ".forks.chain_a_weth");
        address chain_a_lzEndpoint = vm.parseTomlAddress(deployConfig, ".forks.chain_a_lz_endpoint_v2");

        string memory chain_b_rpc = vm.parseTomlString(deployConfig, ".forks.chain_b_rpc_url");
        address chain_b_cross_l2_prover_address =vm.parseTomlAddress(deployConfig, ".forks.chain_b_cross_l2_prover_address");
        chain_b_current_wethAddress = vm.parseTomlAddress(deployConfig, ".forks.chain_b_weth");
        address chain_b_lzEndpoint = vm.parseTomlAddress(deployConfig, ".forks.chain_b_lz_endpoint_v2");

        supportedChains[0] = ChainInfo(vm.createFork(chain_a_rpc),1); // eth mainnet
        supportedChains[1] = ChainInfo(vm.createFork(chain_b_rpc),1); // optimism mainnet

        treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");

        // ############## Create Fork to test ##############
        vm.createSelectFork(chain_b_rpc); // By default op-maininet

        // ################ Deploy Event validator #################
        eventValidator = new EventValidator((chain_b_cross_l2_prover_address));

        // ############# Deploy proxyAdmin ####################
        vm.prank(owner);
        proxyAdmin = address(new ProxyAdmin{salt: "proxyAdmin"}(owner));
        vm.label(proxyAdmin, "proxyAdmin");

        // ################ Deploy underlyingAsset #################
        vm.prank(owner);
        underlyingAsset = new TestERC20(underlyingAssetName, underlyingAssetSymbol, underlyingAssetDecimals);
        vm.label(address(underlyingAsset), "underlyingAsset");

        // ################ Deploy LendingPoolAddressesProvider ################
        bytes32 lp_type = keccak256("OpSuperchain_LENDING_POOL");
        lpAddressProvider1 = new LendingPoolAddressesProvider("TUSDC", owner, proxyAdmin, lp_type);
        lp_type = keccak256("ARB_LENDING_POOL");
        lpAddressProvider2 = new LendingPoolAddressesProvider("TUSDC", owner, proxyAdmin, lp_type);

        // ################ Deploy LendingPool Implementation ################
        vm.prank(owner);
        implementationLp = new LendingPool();
        vm.prank(owner);
        implementationLp.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider1)));
        vm.label(address(implementationLp), "implementationLp");

        // ################ Set LendingPoolImpl in LendingPoolAddressesProvider ################
        vm.prank(owner);
        lpAddressProvider1.setLendingPoolImpl(address(implementationLp));

        proxyLp = LendingPool(lpAddressProvider1.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // ################ Deploy Router ################
        router = new Router{salt: "router"}();
        router.initialize(address(proxyLp), address(lpAddressProvider1), address(eventValidator));
        vm.deal(address(router), 100 ether);

        vm.label(address(lpAddressProvider1), "lpAddressProvider1");
        vm.label(address(lpAddressProvider2), "lpAddressProvider2");

        // ################ Deploy LayerZeroEndpoint ################

        lzEndpoint = EndpointV2(chain_b_lzEndpoint);

        // ################ Deploy SuperAsset ################
        vm.prank(owner);
        superAsset =
            new SuperAsset(address(underlyingAsset), superAssetTokenName, superAsseTokenSymbol, chain_b_current_wethAddress);
        vm.prank(owner);
        superAssetWeth =
            new SuperAsset(address(chain_b_current_wethAddress), superAssetTokenName, superAsseTokenSymbol, chain_b_current_wethAddress);

        vm.label(address(superAsset), "superAsset");

        // ################ Deploy RVaultAsset ################
        vm.startPrank(owner);

        rVaultAsset1 = address(new RVaultAsset{salt: "rVaultAsset1Impl"}());

        IRVaultAsset(rVaultAsset1).initialize(
            address(superAsset),
            ILendingPoolAddressesProvider(address(lpAddressProvider1)),
            address(lzEndpoint),
            _delegate,
            rVaultAssetTokenName1,
            rVaultAssetTokenSymbol1,
            underlyingAssetDecimals,
            1 days,
            1000 ether,
            200000,
            500000
        );
        rVaultAsset2 = address(new RVaultAsset{salt: "rVaultAsset2Impl"}());
        IRVaultAsset(rVaultAsset2).initialize(
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
            500000
        );
        vm.stopPrank();

        // ################ Deploy incentives controller ################
        vm.prank(owner);
        incentivesController = address(new IncentivesController{salt: "incentivesController"}());

        // ################ Deploy RToken ################
        vm.prank(owner);
        RToken rToken = new RToken{salt: "rToken"}();

        vm.prank(owner);
        rToken.initialize(
            ILendingPool(address(proxyLp)),
            treasury,
            address(rVaultAsset1),
            IAaveIncentivesController(incentivesController),
            ILendingPoolAddressesProvider(address(lpAddressProvider1)),
            underlyingAsset.decimals(),
            rTokenName1,
            rTokenSymbol1,
            bytes(""),
            address(eventValidator)
        );

        // ################ Deploy VariableDebtToken ################
        vm.prank(owner);
        VariableDebtToken variableDebtTokenImpl = new VariableDebtToken{salt: "variableDebtTokenImpl"}();
        vm.prank(owner);
        variableDebtTokenImpl.initialize(
            ILendingPool(address(implementationLp)),
            address(underlyingAsset),
            IAaveIncentivesController(incentivesController),
            underlyingAssetDecimals,
            variableDebtTokenName,
            variableDebtTokenSymbol,
            "v"
        );

        // ################ Set addresses in LpAddressesProvider ################
        vm.prank(owner);
        lpAddressProvider1.setPoolAdmin(poolAdmin1);
        vm.prank(owner);
        lpAddressProvider1.setRelayer(relayer);
        vm.prank(owner);
        lpAddressProvider1.setRouter(address(router));

        // ################ Deploy LendingPoolConfigurator ################
        lpConfigurator = new LendingPoolConfigurator();
        lpConfigurator.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider1)), proxyAdmin);

        // ################ Deploy proxy configurator ################
        vm.prank(owner);
        lpAddressProvider1.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider1.getLendingPoolConfigurator());

        // ################ Activate Reserves ################
        vm.prank(poolAdmin1);
        proxyConfigurator.activateReserve(address(rVaultAsset1));

        // ################ Deploy DefaultReserveInterestRateStrategy ################
        strategy = address(
            new DefaultReserveInterestRateStrategy(
                ILendingPoolAddressesProvider(address(lpAddressProvider1)),
                0.8 * 1e27, // optimalUtilizationRate
                0.02 * 1e27, // baseVariableBorrowRate
                0.04 * 1e27, // variableRateSlope1
                0.75 * 1e27 // variableRateSlope2
            )
        );
        vm.label(strategy, "DefaultReserveInterestRateStrategy");
        // ################ Set RVaultAsset for underlying ################
        vm.prank(poolAdmin1);
        proxyConfigurator.setRvaultAssetForUnderlying(address(underlyingAsset), address(rVaultAsset1));

        // ################ Initialize reserve ################

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].rTokenName = rTokenName1;
        input[0].rTokenSymbol = rTokenSymbol1;
        input[0].variableDebtTokenImpl = address(variableDebtTokenImpl);
        input[0].variableDebtTokenName = variableDebtTokenName;
        input[0].variableDebtTokenSymbol = variableDebtTokenSymbol;
        input[0].interestRateStrategyAddress = strategy;
        input[0].treasury = treasury;
        input[0].incentivesController = incentivesController;
        input[0].superAsset = address(superAsset);
        input[0].underlyingAsset = address(rVaultAsset1);
        input[0].underlyingAssetDecimals = underlyingAssetDecimals;
        input[0].underlyingAssetName = underlyingAssetName;
        input[0].params = "v";
        input[0].salt = "salt";
        input[0].rTokenImpl = address(rToken);

        vm.prank(poolAdmin1);
        proxyConfigurator.batchInitReserve(input);
    }
}
