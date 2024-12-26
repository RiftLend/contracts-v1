// // SPDX-License-Identifier: agpl-3.0
// pragma solidity 0.8.25;

// import {Test} from "forge-std/Test.sol";
// import {TestPlus} from "@solady-test/utils/TestPlus.sol";
// import {Vm} from "forge-std/Vm.sol";
// import {console} from "forge-std/console.sol";

// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// import {ILendingPoolAddressesProvider} from "../../src/interfaces/ILendingPoolAddressesProvider.sol";
// import {ILendingPoolConfigurator} from "../../src/interfaces/ILendingPoolConfigurator.sol";
// import "../../src/interfaces/ILendingPool.sol";

// import {MockERC20} from "../../src/tokenization/MockERC20.sol";
// import {SuperchainAsset} from "../../src/SuperchainAsset.sol";
// import {RToken} from "../../src/tokenization/RToken.sol";
// import {StableDebtToken} from "../../src/tokenization/StableDebtToken.sol";
// import {VariableDebtToken} from "../../src/tokenization/VariableDebtToken.sol";
// import {LendingPool} from "../../src/LendingPool.sol";
// import {Router} from "../../src/Router.sol";
// import {LendingPoolAddressesProvider} from "../../src/configuration/LendingPoolAddressesProvider.sol";
// import {LendingPoolConfigurator} from "../../src/LendingPoolConfigurator.sol";
// import {DefaultReserveInterestRateStrategy} from "../../src/DefaultReserveInterestRateStrategy.sol";
// import {LendingRateOracle} from "../../src/LendingRateOracle.sol";
// // import "@contracts-bedrock/L2/interfaces/ICrossL2Inbox.sol";

// contract BaseTest is Test, TestPlus {

//     // assets
//     MockERC20 public Underlying;
//     SuperchainAsset public superchainAsset;
//     RToken public rTokenImpl;
//     StableDebtToken public stabledebtTokenImpl;
//     VariableDebtToken public variabledebtTokenImpl;

//     // system contracts
//     LendingPoolAddressesProvider public lpAddressProvider;
//     LendingPoolConfigurator public lpConfigurator;
//     LendingPoolConfigurator public proxyConfigurator;
//     DefaultReserveInterestRateStrategy public strategy;
//     LendingRateOracle public oracle;
//     LendingPool public implementationLp;
//     LendingPool public proxyLp ;
//     Router public router;
//     ProxyAdmin public proxyAdminContract;

//     struct temps {
//         address owner;
//         address alice;
//         address bob;
//         address emergencyAdmin;
//         address proxyAdmin;
//         address poolAdmin;
//         address relayer;
//         address router;
//         address lendingPoolConfigurator;
//         address lendingPoolAddressesProvider;
//         mapping (address underlyingAsset => Market) markets;
//     }

//     struct Market {
//         uint256 marketId;
//         address underlyingAsset;
//         address rTokenImpl;
//         address stableDebtTokenImpl;
//         address variableDebtTokenImpl;
//         address superchainAsset;
//         address aToken;
//         address variableDebtToken;
//         address stableDebtToken;
//         address interestRateStrategy;
//         address treasury;
//         address incentivesController;
//     }

//     address testToken;
//     mapping (uint256 chainId => temps) public config;

//     // chains
//     uint256[2] internal chainId;
//     string[2] internal rpcs = ["https://mainnet.optimism.io/", "https://mainnet.base.org"];

//     function setUp() public {
//         address owner = _randomNonZeroAddress();
//         for (uint256 i = 0; i < rpcs.length; i++) {
//             _configure(i, rpcs[i], owner);
//         }
//     }

//     function _configure(uint256 _i, string memory _rpc, address _owner) internal {
//         chainId[_i] = vm.createFork(_rpc);
//         vm.selectFork(chainId[_i]);
//         temps storage t = config[chainId[_i]];

//         t.owner = _owner;
//         t.emergencyAdmin = _owner;
//         t.proxyAdmin = _owner;
//         t.poolAdmin = vm.addr(100);
//         t.alice = vm.addr(1);
//         t.bob = vm.addr(2);
//         t.relayer = vm.addr(3);

//         // Underlying
//         Underlying = new MockERC20("Mock rupee","Underlying");
//         vm.label(address(Underlying), "Underlying");
//         Underlying.mint(t.alice, 1000_000);

//         // implementation aToken
//         rTokenImpl = new RToken();

//         // implementation stabledebtToken
//         stabledebtTokenImpl = new StableDebtToken();

//         // implementation variabledebtToekn
//         variabledebtTokenImpl = new VariableDebtToken();

//         // proxyAdmin
//         vm.prank(t.owner);
//         proxyAdminContract = new ProxyAdmin();
//         t.proxyAdmin = address(proxyAdminContract);

//         // lendingPoolAddressProvider
//         lpAddressProvider = new LendingPoolAddressesProvider("Underlying",t.owner,t.proxyAdmin);
//         vm.label(address(lpAddressProvider), "lpAddressProvider");

//         // superchainAsset for opMainnet
//         superchainAsset = new SuperchainAsset("superchainAsset","SCA",18,address(Underlying),ILendingPoolAddressesProvider(address(lpAddressProvider)),_owner);
//         vm.label(address(superchainAsset), "superchainAsset");

//         // implementation LendingPool
//         implementationLp = new LendingPool();
//         vm.label(address(implementationLp), "implementationLp");

//         // proxy LendingPool
//         vm.prank(t.owner);
//         lpAddressProvider.setLendingPoolImpl(address(implementationLp));
//         proxyLp = LendingPool(lpAddressProvider.getLendingPool());
//         vm.label(address(proxyLp), "proxyLp");

//         router = new Router();
//         router.initialize(address(proxyLp), address(lpAddressProvider));
//         t.router = address(router);

//         // settings in addressProvider
//         vm.prank(t.owner);
//         lpAddressProvider.setPoolAdmin(t.poolAdmin);

//         // relayer in addressprovider
//         vm.startPrank(t.owner);
//         lpAddressProvider.setRelayer(t.relayer);
//         lpAddressProvider.setRouter(t.router);
//         vm.stopPrank();

//         // implementation configurator
//         lpConfigurator = new LendingPoolConfigurator();

//         // proxy configurator
//         vm.prank(t.owner);
//         lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
//         proxyConfigurator = LendingPoolConfigurator(lpAddressProvider.getLendingPoolConfigurator());

//         // strategy
//         strategy = new DefaultReserveInterestRateStrategy(ILendingPoolAddressesProvider(address(lpAddressProvider)),1,2,3,4,5,6);

//         // lendingRateOracle
//         oracle = new LendingRateOracle(t.owner);
//         vm.prank(t.owner);
//         lpAddressProvider.setLendingRateOracle(address(oracle));

//         t.markets[address(Underlying)] = Market({
//             marketId: 1,
//             underlyingAsset: address(Underlying),
//             rTokenImpl: address(rTokenImpl),
//             stableDebtTokenImpl: address(stabledebtTokenImpl),
//             variableDebtTokenImpl: address(variabledebtTokenImpl),
//             superchainAsset: address(superchainAsset),
//             aToken: address(rTokenImpl),
//             variableDebtToken: address(variabledebtTokenImpl),
//             stableDebtToken: address(stabledebtTokenImpl),
//             interestRateStrategy: address(strategy),
//             treasury: vm.addr(35),
//             incentivesController: vm.addr(17)
//         });
//     }
// }

// contract Helpers is BaseTest {
//     Identifier[] _identifier;
//     bytes[] _data;
//     Vm.Log[] entries;

//     function _deposit(
//         uint256 chainId,
//         address caller,
//         address asset,
//         uint256[] memory amounts,
//         address onBehalfOf,
//         uint16 referralCode,
//         uint256[] memory chainIds
//     ) internal {
//         //arrange
//         temps storage t = config[chainId];

//         ILendingPoolConfigurator.InitReserveInput[] memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
//         input[0].rTokenImpl = address(rTokenImpl);
//         input[0].stableDebtTokenImpl = address(stabledebtTokenImpl);
//         input[0].variableDebtTokenImpl = address(variabledebtTokenImpl);
//         input[0].underlyingAssetDecimals = 18;
//         input[0].interestRateStrategyAddress = address(strategy);
//         input[0].underlyingAsset = address(asset);
//         input[0].treasury = vm.addr(35);
//         input[0].incentivesController = vm.addr(17);
//         input[0].superchainAsset = address(superchainAsset);
//         input[0].underlyingAssetName = "Mock Underlying";
//         input[0].rTokenName = "aToken-Underlying";
//         input[0].rTokenSymbol = "aUnderlying";
//         input[0].variableDebtTokenName = "vDebtToken";
//         input[0].variableDebtTokenSymbol = "vDT";
//         input[0].stableDebtTokenName = "sDebtToken";
//         input[0].stableDebtTokenSymbol = "sDT";
//         input[0].params = "v";
//         input[0].salt = "salt";
//         vm.prank(t.poolAdmin);
//         proxyConfigurator.batchInitReserve(input);

//         vm.prank(t.alice);
//         MockERC20(asset).approve(address(proxyLp),1000);

//         // act
//         vm.prank(caller);
//         vm.recordLogs();
//         router.deposit(asset, amounts, onBehalfOf, referralCode, chainIds);
//         entries = vm.getRecordedLogs();

//         _identifier.push(Identifier(
//             address(0x4200000000000000000000000000000000000023),
//             block.number,
//             0,
//             block.timestamp,
//             block.chainid
//         ));

//         (
//             uint256 fromChainId,
//             address sender,
//             address asset,
//             uint256 amount,
//             address onBehalfOf,
//             uint16 referralCode
//         ) = abi.decode(entries[0].data,(uint256, address, address, uint256, address, uint16));
//         bytes32 _selector = CrossChainDeposit.selector;

//         _data.push(abi.encode(
//             _selector,
//             fromChainId,
//             bytes32(0),
//             sender,
//             asset,
//             amount,
//             onBehalfOf,
//             referralCode
//         ));
//         console.log(chainId);
//         vm.prank(t.relayer);
//         router.dispatch(_identifier, _data);
//     }

//     // function _borrow(
//     //     address caller,
//     //     address asset,
//     //     uint256[] memory amounts,
//     //     uint256[] memory interestRateMode,
//     //     uint16 referralCode,
//     //     address onBehalfOf,
//     //     uint256 sendToChainId,
//     //     uint256[] memory chainIds
//     // ) internal {
//     //     // arrange

//     //     // act
//     //     vm.prank(caller);
//     //     proxyLp.borrow(asset, amounts, interestRateMode, referralCode, onBehalfOf, sendToChainId, chainIds);
//     // }

//     function _withdraw(
//         address caller,
//         address asset,
//         uint256[] memory amounts,
//         address to,
//         uint256 toChainId,
//         uint256[] memory chainIds
//     ) internal {
//         //arrange

//         // act
//         vm.prank(caller);
//         router.withdraw(asset, amounts, to, toChainId, chainIds);
//     }

// }
