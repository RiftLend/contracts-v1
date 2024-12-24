// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ILendingPoolAddressesProvider} from "../src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "../src/interfaces/ILendingPoolConfigurator.sol";

import {MockERC20} from "../src/tokenization/MockERC20.sol";
import {SuperchainAsset} from "../src/SuperchainAsset.sol";
import {AToken} from "../src/tokenization/AToken.sol";
import {StableDebtToken} from "../src/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "../src/tokenization/VariableDebtToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {Router} from "../src/Router.sol";
import {LendingPoolAddressesProvider} from "../src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolConfigurator} from "../src/LendingPoolConfigurator.sol";
import {DefaultReserveInterestRateStrategy} from "../src/DefaultReserveInterestRateStrategy.sol";
import {LendingRateOracle} from "../src/LendingRateOracle.sol";

contract BaseTest is Test {

    // chains
    uint256 public opMainnet;
    uint256 public base;

    // participants
    address public owner = vm.addr(1000);
    address public proxyAdmin;
    address public poolAdmin = vm.addr(100);
    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

    // markets
    string public marketId;

    // assets
    MockERC20 public Underlying;
    SuperchainAsset public superchainAsset;
    AToken public aTokenImpl;
    StableDebtToken public stabledebtTokenImpl;
    VariableDebtToken public variabledebtTokenImpl;

    // system contracts
    LendingPoolAddressesProvider public lpAddressProvider;
    LendingPoolConfigurator public lpConfigurator;
    LendingPoolConfigurator public proxyConfigurator;
    DefaultReserveInterestRateStrategy public strategy;
    LendingRateOracle public oracle;
    LendingPool public implementationLp;
    LendingPool public proxyLp ;
    Router public router;
    ProxyAdmin public proxyAdminContract;

    function setUp() public {
        vm.label(proxyAdmin, 'proxyAdmin');
        vm.label(owner, 'owner');
        vm.label(alice, 'alice');

        _configureOpMainnet();
        _configureBase();

    }

    function _configureOpMainnet() internal {
        opMainnet = vm.createSelectFork("https://mainnet.optimism.io/");
        
        // Underlying
        Underlying = new MockERC20("Mock rupee","Underlying"); 
        vm.label(address(Underlying), "Underlying");
        Underlying.mint(alice, 1000_000);

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // proxyAdmin
        vm.prank(owner);
        proxyAdminContract = new ProxyAdmin();
        proxyAdmin = address(proxyAdminContract);

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("Underlying",owner,proxyAdmin);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for opMainnet
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(Underlying),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");
        
        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        router = new Router();
        router.initialize(address(proxyLp), address(lpAddressProvider));

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(poolAdmin);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

        // lendingRateOracle
        oracle = new LendingRateOracle(owner);
        vm.prank(owner);
        lpAddressProvider.setLendingRateOracle(address(oracle));
    }

    function _configureBase() internal {
        base = vm.createSelectFork("https://mainnet.base.org");
        
        // Underlying
        Underlying = new MockERC20("Mock rupee","Underlying"); 
        vm.label(address(Underlying), "Underlying");
        Underlying.mint(alice, 1000_000);

        // implementation aToken
        aTokenImpl = new AToken();
        
        // implementation stabledebtToken
        stabledebtTokenImpl = new StableDebtToken();
        
        // implementation variabledebtToekn
        variabledebtTokenImpl = new VariableDebtToken();

        // proxyAdmin
        vm.prank(owner);
        proxyAdminContract = new ProxyAdmin();
        proxyAdmin = address(proxyAdminContract);

        // lendingPoolAddressProvider
        lpAddressProvider = new LendingPoolAddressesProvider("Underlying",owner,proxyAdmin);
        vm.label(address(lpAddressProvider), "lpAddressProvider");
        
        // superchainAsset for base
        superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(Underlying),ILendingPoolAddressesProvider(address(lpAddressProvider)),owner);
        vm.label(address(superchainAsset), "superchainAsset");

        // implementation LendingPool
        implementationLp = new LendingPool();
        vm.label(address(implementationLp), "implementationLp");

        // proxy LendingPool
        vm.prank(owner);
        lpAddressProvider.setLendingPoolImpl(address(implementationLp));
        proxyLp = LendingPool(lpAddressProvider.getLendingPool());
        vm.label(address(proxyLp), "proxyLp");

        router = new Router();
        router.initialize(address(proxyLp), address(lpAddressProvider));

        // settings in addressProvider
        vm.prank(owner);
        lpAddressProvider.setPoolAdmin(poolAdmin);

        // implementation configurator
        lpConfigurator = new LendingPoolConfigurator();

        // proxy configurator
        vm.prank(owner);
        lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
        proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

        // strategy
        strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

        // lendingRateOracle
        oracle = new LendingRateOracle(owner);
        vm.prank(owner);
        lpAddressProvider.setLendingRateOracle(address(oracle));

    }
}

struct Identifier {
    address origin;
    uint256 blockNumber;
    uint256 logIndex;
    uint256 timestamp;
    uint256 chainId;
}

contract Helpers is BaseTest {
    function _deposit(
        address caller,
        address asset,
        uint256[] memory amounts,
        address onBehalfOf,
        uint16 referralCode,
        uint256[] memory chainIds
    ) internal {
        //arrange
        ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
        input[0].aTokenImpl = address(aTokenImpl);
        input[0].stableDebtTokenImpl = address(stabledebtTokenImpl);
        input[0].variableDebtTokenImpl = address(variabledebtTokenImpl);
        input[0].underlyingAssetDecimals = 18;
        input[0].interestRateStrategyAddress = address(strategy);
        input[0].underlyingAsset = address(asset);
        input[0].treasury = vm.addr(35);
        input[0].incentivesController = vm.addr(17);
        input[0].superchainAsset = address(superchainAsset);
        input[0].underlyingAssetName = "Mock Underlying";
        input[0].aTokenName = "aToken-Underlying";
        input[0].aTokenSymbol = "aUnderlying";
        input[0].variableDebtTokenName = "vDebtToken";
        input[0].variableDebtTokenSymbol = "vDT";
        input[0].stableDebtTokenName = "sDebtToken";
        input[0].stableDebtTokenSymbol = "sDT";
        input[0].params = "v";
        input[0].salt = "salt";
        vm.prank(poolAdmin);
        proxyConfigurator.batchInitReserve(input);

        vm.prank(alice);
        MockERC20(asset).approve(address(proxyLp),1000);

        // act
        vm.prank(caller);
        vm.recordLogs();
        router.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        
        Identifier _identifier;
        _identifier.origin = address(0x4200000000000000000000000000000000000023);//L2ToL2CrossDomainMessenger
        _identifier.blockNumber = block.number;
        _identifier.logIndex += 1; 
        _identifier.timestamp = block.timestamp;
        _identifier.chainId = block.chainid;
        bytes data;
        data = abi.encode(deposit.selector, );
        router.dispatch(_identifier, _data);
    }

    // function _borrow(
    //     address caller,
    //     address asset,
    //     uint256[] memory amounts,
    //     uint256[] memory interestRateMode,
    //     uint16 referralCode,
    //     address onBehalfOf,
    //     uint256 sendToChainId,
    //     uint256[] memory chainIds
    // ) internal {
    //     // arrange

    //     // act
    //     vm.prank(caller);
    //     proxyLp.borrow(asset, amounts, interestRateMode, referralCode, onBehalfOf, sendToChainId, chainIds);
    // }

    function _withdraw(
        address caller,
        address asset,
        uint256[] memory amounts,
        address to,
        uint256 toChainId,
        uint256[] memory chainIds
    ) internal {
        //arrange
        
        // act
        vm.prank(caller);
        router.withdraw(asset, amounts, to, toChainId, chainIds);
    }
    
}

contract LendingPoolTest is Helpers {

    // function testBorrow() public {
    //     vm.selectFork(opMainnet);

    //     // history : deposit

    //     /////////////////////////////////////////////////////////////////////////////////////////////////////
    //     // set inputs and call action
    //     address caller = bob;
    //     address asset = address(Underlying);
    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = 800;
    //     uint256[] memory interestRateMode = new uint256[](1);
    //     interestRateMode[0] = 1;
    //     uint16 referralCode = 0;
    //     address onBehalfOf = bob;
    //     uint256 sendToChainId = block.chainid;
    //     uint256[] memory chainIds = new uint256[](1);
    //     chainIds[0] = block.chainid;
    //     /***************************************************************************************************/
    //     _borrow(caller, asset, amounts, interestRateMode, referralCode, onBehalfOf, sendToChainId, chainIds);
    //     /***************************************************************************************************/


    //     // assert
    //     address superchainAsset_ = proxyLp.getReserveData(address(Underlying)).superchainAssetAddress;
    //     address aToken_ = proxyLp.getReserveData(address(Underlying)).aTokenAddress;
    //     // 1. underlying
    //     assertEq(Underlying.balanceOf(superchainAsset_), 200);

    //     // 2. superchainAsset
    //     assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 200);

    //     // 3. aToken
    //     assertEq(AToken(aToken_).balanceOf(alice), 200);

    //     // 4. sDT

    //     // 5. vDT
    // }

    function testDeposit() public {
        vm.selectFork(opMainnet);

        /////////////////////////////////////////////////////////////////////
        // set inputs and call action
        address caller = alice;
        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        /*******************************************************************/
        _deposit(caller, asset, amounts, onBehalfOf, referralCode, chainIds);
        /*******************************************************************/

        // assert
        address superchainAsset_ = proxyLp.getReserveData(address(Underlying)).superchainAssetAddress;
        address aToken_ = proxyLp.getReserveData(address(Underlying)).aTokenAddress;
        // 1. underlying
        assertEq(Underlying.balanceOf(superchainAsset_), 1000);

        // 2. superchainAsset
        assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 1000);

        // 3. aToken
        assertEq(AToken(aToken_).balanceOf(alice), 1000);

    }

    function testWithdraw() public {
        vm.selectFork(opMainnet);

        // history : deposit
        address caller = alice;
        address asset = address(Underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;
        address onBehalfOf = alice;
        uint16 referralCode = 0;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        _deposit(caller, asset, amounts, onBehalfOf, referralCode, chainIds);

        ///////////////////////////////////////////////////////////
        // set inputs and call action
        caller = alice;
        asset = address(Underlying);
        amounts[0] = 800;
        address to = alice;
        uint256 toChainId = block.chainid;
        chainIds[0] = block.chainid;
        /*********************************************************/
        _withdraw(caller, asset, amounts, to, toChainId, chainIds);      
        /*********************************************************/

        // assert
        address superchainAsset_ = proxyLp.getReserveData(address(Underlying)).superchainAssetAddress;
        address aToken_ = proxyLp.getReserveData(address(Underlying)).aTokenAddress;
        // 1. underlying
        assertEq(Underlying.balanceOf(superchainAsset_), 200);

        // 2. superchainAsset
        assertEq(SuperchainAsset(superchainAsset_).balanceOf(aToken_), 200);

        // 3. aToken
        assertEq(AToken(aToken_).balanceOf(alice), 200);
    }

}