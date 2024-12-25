// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {ILendingPoolAddressesProvider} from "../../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../../src/interfaces/ILendingPoolConfigurator.sol";

import {TestERC20} from "../utils/TestERC20.sol";
import {SuperAsset} from "../../src/SuperAsset.sol";
import {AToken} from "../../src/tokenization/AToken.sol";
import {StableDebtToken} from "../../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {LendingPoolAddressesProvider} from "../../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../../src/DefaultReserveInterestRateStrategy.sol";
import {ProxyAdmin} from "src/interop-std/src/utils/SuperProxyAdmin.sol";

import "../../src/interfaces/ISuperAsset.sol";

contract LendingPoolTest is Test {
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
        address aTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        address SuperAsset;
        address aToken;
        address variableDebtToken;
        address stableDebtToken;
        address interestRateStrategy;
        address treasury;
        address incentivesController;
    }

    address testToken;
    mapping(uint256 chainId => temps) public config;

    // Util addresses
    address owner = makeAddr("owner");
    address poolAdmin1 = makeAddr("poolAdmin1");
    address router = makeAddr("router");

    address relayer = makeAddr("relayer");
    address emergencyAdmin = makeAddr("emergencyAdmin");
    address alice = makeAddr("alice");

    LendingPool proxyLp;
    LendingPool implementationLp;
    ISuperAsset superAsset;
    address superProxyAdmin;
    TestERC20 INR;
    TestERC20 underlyingAsset;
    LendingPoolConfigurator lpConfigurator;
    LendingPoolConfigurator proxyConfigurator;
    LendingPoolAddressesProvider lpAddressProvider;

    function setUp() public {
        uint64 _chainId = 1;
        // string memory _rpc = ""

        temps storage t = config[_chainId];
        // vm.createSelectFork(_rpc);

        t.owner = owner;
        t.emergencyAdmin = emergencyAdmin;

        // Deploy underlyingAsset
        underlyingAsset = new TestERC20("TUSDC", "USDC", 6);
        vm.label(address(underlyingAsset), "underlyingAsset");

        // Deploy SuperProxyAdmin
        superProxyAdmin = address(new ProxyAdmin{salt: "superProxyAdmin"}(owner, _chainId));
        vm.label(superProxyAdmin, "superProxyAdmin");
        t.proxyAdmin = superProxyAdmin;

        // deploy implementations
        address aTokenImpl = address(new AToken{salt: "aTokenImpl"}());
        address stableDebtTokenImpl = address(new StableDebtToken{salt: "stableDebtTokenImpl"}());
        address variableDebtTokenImpl = address(new VariableDebtToken{salt: "variableDebtTokenImpl"}());

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("TUSDC", owner, t.proxyAdmin);
        vm.label(address(lpAddressProvider), "lpAddressProvider");

        address lzEndpoint = makeAddr("lzEndpoint");
        address lzDelegate = makeAddr("lzdelegate");

        // SuperAsset for opMainnet
        superAsset = ISuperAsset(
            address(
                new SuperAsset(
                    address(underlyingAsset),
                    lzEndpoint
                )
            )
        );
        vm.label(address(superAsset), "SuperAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(poolAdmin1);

        vm.prank(owner);
        lpAddressProvider.setRelayer(relayer);

        vm.prank(owner);
        lpAddressProvider.setRouter(router);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // arrange
        // vm.selectFork(opMainnet);

        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].aTokenImpl = address(aTokenImpl);
        input[0].stableDebtTokenImpl = address(stableDebtTokenImpl);
        input[0].variableDebtTokenImpl = address(variableDebtTokenImpl);
        input[0].underlyingAssetDecimals = 6;
        input[0].interestRateStrategyAddress = address(0x0);
        input[0].underlyingAsset = address(INR);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].underlyingAssetName = "Mock USDC";
        input[0].aTokenName = "aToken-TUSDC";
        input[0].aTokenSymbol = "aTUSDC";
        input[0].variableDebtTokenName = "vDebt";
        input[0].variableDebtTokenSymbol = "vDBT";
        input[0].stableDebtTokenName = "vStable";
        input[0].stableDebtTokenSymbol = "vSBT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(poolAdmin1);
        proxyConfigurator.batchInitReserve(input);
    }

    function testDeposit() public {
        // act
        address asset = address(underlyingAsset);
        uint256[1] memory amounts;
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint16[1] memory chainIds;
        chainIds[0] = 1;

        vm.prank(router);
        proxyLp.deposit(alice, asset, amounts[0], onBehalfOf, referralCode);

        // assert
        // 1. superchainAsset
        address aToken_ = proxyLp.getReserveData(asset).aTokenAddress;
        superAsset = ISuperAsset(lpAddressProvider.getSuperAsset());

        assertEq(superAsset.balanceOf(aToken_), 1000);

        // 2. aToken
        // assertEq((aToken).balanceOf(alice), 1000);
        // assertEq((aToken).balanceOf(treasury), 10);
    }
}
