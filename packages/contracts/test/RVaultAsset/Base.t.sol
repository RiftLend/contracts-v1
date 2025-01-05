// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "../../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../../src/interfaces/ILendingPoolConfigurator.sol";
import {ICrossL2Prover} from "../../src/interfaces/ICrossL2Prover.sol";
import {ISuperAsset} from "../../src/interfaces/ISuperAsset.sol";
import {IAaveIncentivesController} from "../../src/interfaces/IAaveIncentivesController.sol";
import {ILendingPool} from "../../src/interfaces/ILendingPool.sol";
import {IRVaultAsset} from "../../src/interfaces/IRVaultAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IncentivesController} from "../utils/IncentivesController.sol";

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {SuperAsset} from "../../src/SuperAsset.sol";
import {RToken} from "../../src/tokenization/RToken.sol";
import {RVaultAsset} from "../../src/RVaultAsset.sol";
import {VariableDebtToken} from "../../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../../src/DefaultReserveInterestRateStrategy.sol";
import {ProxyAdmin} from "src/interop-std/src/utils/SuperProxyAdmin.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {MockLayerZeroEndpointV2} from "../utils/MockLayerZeroEndpointV2.sol";
import {Router} from "../../src/Router.sol";
import {EventValidator} from "../../src/libraries/EventValidator.sol";

contract Base is Test {
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
    address superProxyAdmin;
    TestERC20 INR;
    TestERC20 underlyingAsset;
    LendingPoolConfigurator lpConfigurator;
    LendingPoolConfigurator proxyConfigurator;
    LendingPoolAddressesProvider lpAddressProvider;
    MockLayerZeroEndpointV2 lzEndpoint;
    Router router;
    address rVaultAsset;

    function setUp() public {
        // ############## Load deploy config ##############
        string memory deployConfigPath = vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml"));
        string memory filePath = string.concat(vm.projectRoot(), deployConfigPath);
        string memory deployConfig = vm.readFile(filePath);

        // ############## Read deploy config variables ##############
        string memory chain_a_rpc = vm.parseTomlString(deployConfig, ".forks.chain_a_rpc_url");
        uint256 chain_a_id = vm.parseTomlUint(deployConfig, ".forks.chain_a_chain_id");
        address chain_a_cross_l2_prover_address =
            vm.parseTomlAddress(deployConfig, ".forks.chain_a_cross_l2_prover_address");

        treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");

        // ############## Create Fork to test ##############
        // uint256 _forkId = vm.createSelectFork(chain_a_rpc);
        vm.createSelectFork(chain_a_rpc);
        uint64 _chainId = uint64(chain_a_id);

        // ################ Deploy Event validator #################
        vm.prank(owner);
        EventValidator eventValidator = new EventValidator((chain_a_cross_l2_prover_address));

        // ############# Deploy SuperProxyAdmin ####################
        vm.prank(owner);
        superProxyAdmin = address(new ProxyAdmin{salt: "superProxyAdmin"}(owner, _chainId));
        vm.label(superProxyAdmin, "superProxyAdmin");

        // ################ Deploy underlyingAsset #################
        string memory underlyingAssetName = "TUSDC";
        string memory underlyingAssetSymbol = "USDC";
        string memory rTokenName = "rTUSDC";
        string memory rTokenSymbol = "rTUSDC";
        string memory rVaultAssetTokenName = "rVaultAsset-TUSDC";
        string memory rVaultAssetTokenSymbol = "rVaultAsset-rTUSDC";
        string memory superAssetTokenName = "superTUSDC";
        string memory superAsseTokenSymbol = "superTUSDC";

        string memory variableDebtTokenName = "vDebt-TUSDC";
        string memory variableDebtTokenSymbol = "vDBT-rTUSDC";
        uint8 underlyingAssetDecimals = 6;

        vm.prank(owner);
        underlyingAsset = new TestERC20(underlyingAssetName, underlyingAssetSymbol, underlyingAssetDecimals);
        vm.label(address(underlyingAsset), "underlyingAsset");
        // ################ Mint underlying tokens to users ################
        vm.prank(owner);
        underlyingAsset.mint(user1, 1000000 ether);

        // ################ Deploy LendingPoolAddressesProvider ################
        bytes32 lp_type = keccak256("OpSuperchain_LENDING_POOL");
        lpAddressProvider = new LendingPoolAddressesProvider("TUSDC", owner, superProxyAdmin, lp_type);

        // ################ Deploy LendingPool Implementation ################
        vm.prank(owner);
        implementationLp = new LendingPool();
        vm.prank(owner);
        implementationLp.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider)));
        vm.label(address(implementationLp), "implementationLp");

        // ################ Set LendingPoolImpl in LendingPoolAddressesProvider ################
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));

        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // ################ Deploy Router ################
        router = new Router{salt: "router"}();
        router.initialize(address(proxyLp), address(lpAddressProvider), address(eventValidator));

        // ################ Deploy LayerZeroEndpoint ################
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        uint32 lzEndpoint_eid = 1;
        vm.prank(owner);
        lzEndpoint = new MockLayerZeroEndpointV2(lzEndpoint_eid, owner);

        // ################ Deploy SuperAsset ################
        vm.prank(owner);
        superAsset = new SuperAsset(
            address(underlyingAsset), address(lzEndpoint), _delegate, superAssetTokenName, superAsseTokenSymbol
        );
        vm.label(address(superAsset), "superAsset");

        // ################ Deploy RVaultAsset ################
        vm.prank(owner);

        rVaultAsset = address(
            new RVaultAsset{salt: "rVaultAssetImpl"}(
                address(underlyingAsset),
                ILendingPoolAddressesProvider(address(lpAddressProvider)),
                address(lzEndpoint),
                _delegate,
                rVaultAssetTokenName,
                rVaultAssetTokenSymbol,
                underlyingAssetDecimals
            )
        );

        // ################ Deploy incentives controller ################
        vm.prank(owner);
        incentivesController = address(new IncentivesController{salt: "incentivesController"}());

        // ################ Deploy RToken ################
        vm.prank(owner);
        RToken rTokenImpl = new RToken{salt: "rTokenImpl"}();

        vm.prank(owner);
        rTokenImpl.initialize(
            ILendingPool(address(proxyLp)),
            treasury,
            address(rVaultAsset),
            IAaveIncentivesController(incentivesController),
            ILendingPoolAddressesProvider(address(lpAddressProvider)),
            underlyingAsset.decimals(),
            underlyingAsset.name(),
            underlyingAsset.symbol(),
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
        lpAddressProvider.setPoolAdmin(poolAdmin1);
        vm.prank(owner);
        lpAddressProvider.setRelayer(relayer);
        vm.prank(owner);
        lpAddressProvider.setRouter(address(router));
        vm.prank(owner);
        lpAddressProvider.setRVaultAsset(rVaultAsset);

        // ################ Deploy LendingPoolConfigurator ################
        lpConfigurator = new LendingPoolConfigurator();
        lpConfigurator.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider)), superProxyAdmin);

        // ################ Deploy proxy configurator ################
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // ################ Activate Reserves ################
        vm.prank(poolAdmin1);
        proxyConfigurator.activateReserve(address(rVaultAsset));

        // ################ Deploy DefaultReserveInterestRateStrategy ################
        address strategy = address(
            new DefaultReserveInterestRateStrategy(
                ILendingPoolAddressesProvider(address(lpAddressProvider)),
                0.8 * 1e27, // optimalUtilizationRate
                0.02 * 1e27, // baseVariableBorrowRate
                0.04 * 1e27, // variableRateSlope1
                0.75 * 1e27 // variableRateSlope2
            )
        );
        vm.label(strategy, "DefaultReserveInterestRateStrategy");

        // ################ Initialize reserve ################

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].rTokenImpl = address(rTokenImpl);
        input[0].rTokenName = rTokenName;
        input[0].rTokenSymbol = rTokenSymbol;
        input[0].variableDebtTokenImpl = address(variableDebtTokenImpl);
        input[0].variableDebtTokenName = variableDebtTokenName;
        input[0].variableDebtTokenSymbol = variableDebtTokenSymbol;
        input[0].interestRateStrategyAddress = strategy;
        input[0].treasury = treasury;
        input[0].incentivesController = incentivesController;
        input[0].superAsset = address(superAsset);
        input[0].underlyingAsset = address(rVaultAsset);
        input[0].underlyingAssetDecimals = underlyingAssetDecimals;
        input[0].underlyingAssetName = underlyingAssetName;
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(poolAdmin1);
        proxyConfigurator.batchInitReserve(input);
    }
}
