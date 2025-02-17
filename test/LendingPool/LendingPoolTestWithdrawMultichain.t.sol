// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

// import {IRVaultAsset} from "src/interfaces/IRVaultAsset.sol";
// import {IOFT} from "src/libraries/helpers/layerzero/IOFT.sol";
// import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
// import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ILendingPool, CrossChainDeposit, CrossChainWithdraw, Withdraw, Deposit} from "src/interfaces/ILendingPool.sol";
// import {IAaveIncentivesController} from "src/interfaces/IAaveIncentivesController.sol";

// import {DataTypes} from "src/libraries/types/DataTypes.sol";
// import {UserConfiguration} from "src/libraries/configuration/UserConfiguration.sol";
// import {Identifier} from "src/libraries/EventValidator.sol";
// import {
//     Origin, MessagingReceipt, ILayerZeroEndpointV2
// } from "src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
// import {ValidationMode} from "src/libraries/EventValidator.sol";
// import {Base} from "../Base.t.sol";
// import {RVaultAsset} from "src/RVaultAsset.sol";
// import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
// import {LendingPool} from "src/LendingPool.sol";
// import {Router} from "src/Router.sol";
// import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
// import {RToken} from "src/tokenization/RToken.sol";
// import {EventValidator} from "src/libraries/EventValidator.sol";
// import {VariableDebtToken} from "src/tokenization/VariableDebtToken.sol";
// import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
// import "forge-std/Vm.sol";
// import {console} from "forge-std/console.sol";
// import "@openzeppelin/contracts/utils/Strings.sol";
// import {SuperAsset} from "src/SuperAsset.sol";
// import {TestERC20} from ".././utils/TestERC20.sol";

// interface IOAppSetPeer {
//     function setPeer(uint32 _eid, bytes32 _peer) external;
//     function endpoint() external view returns (ILayerZeroEndpointV2 iEndpoint);
// }

// /**
//  * @title LendingPoolTestWithdraw
//  * @notice Test contract for cross-chain withdrawal functionality in the lending pool system
//  * @dev Tests the complete flow of deposits and withdrawals across different chains using LayerZero
//  */
// contract LendingPoolTestWithdrawMultichain is Base {
//     using Strings for uint256;

//     struct ChainAddresses {
//         address endpoint;
//         uint256 chainId; // Network chain ID
//         LendingPoolAddressesProvider lpAddressProvider;
//         LendingPool lendingPool;
//         LendingPool lendingPoolImpl;
//         LendingPoolConfigurator configurator;
//         Router router;
//         IRVaultAsset rVaultAsset;
//         RToken rToken;
//         VariableDebtToken variableDebtToken;
//     }

//     mapping(uint256 => ChainAddresses) private chainAddresses;
//     /**
//      * @notice Sets up the complete test environment
//      * @dev Initializes all necessary contracts and configurations for cross-chain testing
//      */

//     function setUp() public virtual override {
//         // Initialize base test setup
//         super.setUp();

//         // ======== Initial User Setup ========
//         // Provide test users with initial ETH balances
//         vm.deal(user1, 1000 ether);
//         vm.deal(user2, 1000 ether);

//         // Initialize LayerZero endpoints using UltraLightNode
//         setUpEndpoints(uint8(supportedChains.length), LibraryType.UltraLightNode);

//         // ======== Deploy Address Providers ========
//         // Create unique identifier for lending pools
//         bytes32 lp_type = keccak256("OpSuperchain_LENDING_POOL");
//         for (uint256 i = 0; i < supportedChains.length; i++) {
//             console.log("Setting up chain id: %s", Strings.toString(supportedChains[i].chainId));
//             uint256 c_id = supportedChains[i].chainId;
//             vm.selectFork(supportedChains[i].forkId);
//             chainAddresses[c_id].endpoint = supportedChains[i].endpoint;
//             vm.startPrank(owner);

//             underlyingAsset = new TestERC20(underlyingAssetName, underlyingAssetSymbol, underlyingAssetDecimals);
//             vm.label(address(underlyingAsset), string(abi.encodePacked("UnderlyingAsset: ", Strings.toString(c_id))));

//             chainAddresses[c_id].lpAddressProvider =
//                 new LendingPoolAddressesProvider("TUSDC", owner, proxyAdmin, lp_type);
//             vm.label(
//                 address(chainAddresses[c_id].lpAddressProvider),
//                 string(abi.encodePacked("lpAddressProvider: ", Strings.toString(c_id)))
//             );

//             LendingPool lendingPoolImpl = new LendingPool();
//             chainAddresses[c_id].lendingPoolImpl = lendingPoolImpl;
//             lendingPoolImpl.initialize(ILendingPoolAddressesProvider(address(chainAddresses[c_id].lpAddressProvider)));
//             vm.label(address(lendingPoolImpl), string(abi.encodePacked("LendingPoolImpl: ", Strings.toString(c_id))));
//             chainAddresses[c_id].lpAddressProvider.setLendingPoolImpl(address(lendingPoolImpl));

//             LendingPool proxyLp = LendingPool(chainAddresses[c_id].lpAddressProvider.getLendingPool());
//             chainAddresses[c_id].lendingPool = proxyLp;
//             vm.label(address(proxyLp), string(abi.encodePacked("ProxyLendingPool: ", Strings.toString(c_id))));
//             LendingPoolConfigurator configuratorImpl = new LendingPoolConfigurator();
//             // Initialize configurators
//             configuratorImpl.initialize(
//                 ILendingPoolAddressesProvider(address(chainAddresses[c_id].lpAddressProvider)), proxyAdmin
//             );
//             // Set configurator implementations in providers
//             chainAddresses[c_id].lpAddressProvider.setLendingPoolConfiguratorImpl(address(configuratorImpl));

//             chainAddresses[c_id].configurator =
//                 LendingPoolConfigurator(chainAddresses[c_id].lpAddressProvider.getLendingPoolConfigurator());
//             // Deploy routers with unique salts
//             Router router = new Router{salt: "RouterContract"}();
//             // Initialize routers with respective components
//             router.initialize(
//                 address(chainAddresses[c_id].lendingPool),
//                 address(chainAddresses[c_id].lpAddressProvider),
//                 address(eventValidator)
//             );
//             chainAddresses[c_id].router = router;

//             // Configure chain A provider
//             chainAddresses[c_id].lpAddressProvider.setPoolAdmin(poolAdmin1);
//             chainAddresses[c_id].lpAddressProvider.setRelayer(relayer);
//             chainAddresses[c_id].lpAddressProvider.setRouter(address(router));

//             superAsset = new SuperAsset(
//                 address(underlyingAsset), superAssetTokenName, superAsseTokenSymbol, supportedChains[i].weth
//             );
//             vm.label(address(superAsset), string(abi.encodePacked("superAsset : ", Strings.toString(c_id))));

//             // Deploy and initialize vault asset for chain A
//             IRVaultAsset _rVaultAsset = IRVaultAsset(_deployOApp(type(RVaultAsset).creationCode, bytes("")));

//             console.log("init rVaultAsset ", address(_rVaultAsset));
//             vm.label(address(_rVaultAsset), string(abi.encodePacked("RVault: ", Strings.toString(c_id))));

//             _rVaultAsset.initialize(
//                 address(superAsset),
//                 ILendingPoolAddressesProvider(address(chainAddresses[c_id].lpAddressProvider)),
//                 address(chainAddresses[c_id].endpoint),
//                 _delegate,
//                 rVaultAssetTokenName1,
//                 rVaultAssetTokenSymbol1,
//                 underlyingAssetDecimals,
//                 1 days,
//                 1000 ether,
//                 200000,
//                 500000
//             );
//             chainAddresses[c_id].rVaultAsset = _rVaultAsset;
//             // Deploy and initialize RTokens
//             RToken _rToken = new RToken{salt: "rTokenContract"}();
//             _rToken.initialize(
//                 ILendingPool(address(chainAddresses[c_id].lendingPool)),
//                 treasury,
//                 address(_rVaultAsset),
//                 IAaveIncentivesController(incentivesController),
//                 ILendingPoolAddressesProvider(address(chainAddresses[c_id].lpAddressProvider)),
//                 underlyingAssetDecimals,
//                 rTokenName1,
//                 rTokenSymbol1,
//                 bytes(""),
//                 address(eventValidator)
//             );
//             // vm.label(address(rToken), string(abi.encodePacked("RToken: ", Strings.toString(c_id))));
//             chainAddresses[c_id].rToken =RToken(_rToken);
//             VariableDebtToken vdebt = new VariableDebtToken{salt: "variableDebtTokenContract"}();

//             vdebt.initialize(
//                 ILendingPool(address(chainAddresses[c_id].lendingPool)),
//                 address(underlyingAsset),
//                 IAaveIncentivesController(incentivesController),
//                 underlyingAssetDecimals,
//                 variableDebtTokenName,
//                 variableDebtTokenSymbol,
//                 "v"
//             );
//             chainAddresses[c_id].variableDebtToken = vdebt;

//             ILendingPoolConfigurator.InitReserveInput[] memory pool_input =
//                 new ILendingPoolConfigurator.InitReserveInput[](1);
//             pool_input[0] = ILendingPoolConfigurator.InitReserveInput({
//                 rTokenName: rTokenName1,
//                 rTokenSymbol: rTokenSymbol1,
//                 variableDebtTokenImpl: address(chainAddresses[c_id].variableDebtToken),
//                 variableDebtTokenName: variableDebtTokenName,
//                 variableDebtTokenSymbol: variableDebtTokenSymbol,
//                 interestRateStrategyAddress: strategy,
//                 treasury: treasury,
//                 incentivesController: incentivesController,
//                 superAsset: address(superAsset),
//                 underlyingAsset: address(address(chainAddresses[c_id].rVaultAsset)),
//                 underlyingAssetDecimals: underlyingAssetDecimals,
//                 underlyingAssetName: underlyingAssetName,
//                 params: "v",
//                 salt: "salt",
//                 rTokenImpl: address(chainAddresses[c_id].rToken)
//             });
//             vm.stopPrank();

//             vm.startPrank(poolAdmin1);
//             // Initialize reserves on both chains
//             chainAddresses[c_id].configurator.batchInitReserve(pool_input);
//             // Activate reserves and set RVaultAsset mappings
//             chainAddresses[c_id].configurator.activateReserve(address(chainAddresses[c_id].rVaultAsset));
//             chainAddresses[c_id].configurator.setRvaultAssetForUnderlying(
//                 address(underlyingAsset), address(chainAddresses[c_id].rVaultAsset)
//             );

//             vm.stopPrank();

//             // Bootstraping initial ETH to contracts for lzCalls
//             vm.deal(address(chainAddresses[c_id].rToken), 100 ether);
//             vm.deal(address(chainAddresses[c_id].router), 100 ether);
//         }

//         // ======== Configure Cross-Chain Communication ========
//         // Setup peer connections between vault assets
//         address[] memory ofts = new address[](supportedChains.length);
//         for (uint256 i = 0; i < ofts.length; i++) {
//             ofts[i] = address(chainAddresses[supportedChains[i].chainId].rVaultAsset);
//         }

//         uint256 size = ofts.length;
//         for (uint256 i = 0; i < size; i++) {
//             IOAppSetPeer localOApp = IOAppSetPeer(ofts[i]);
//             for (uint256 j = 0; j < size; j++) {
//                 if (i == j) continue;
//                 IOAppSetPeer remoteOApp = IOAppSetPeer(ofts[j]);
//                 uint32 remoteEid = (remoteOApp.endpoint()).eid();
//                 vm.prank(owner);
//                 localOApp.setPeer(remoteEid, addressToBytes32(address(remoteOApp)));
//             }
//         }

//         // Initialize user balances and approvals for each vault
//         for (uint256 i = 0; i < supportedChains.length; i++) {

//             address rVaultAsset = address(chainAddresses[supportedChains[i].chainId].rVaultAsset);
//             console.log(rVaultAsset);
//             vm.selectFork(supportedChains[i].forkId);
//             // Provide initial underlying token balances
//             deal(address(underlyingAsset), user1, INITIAL_BALANCE);
//             deal(address(underlyingAsset), user2, INITIAL_BALANCE);
//             deal(address(underlyingAsset), liquidityProvider, INITIAL_BALANCE);

//             // Setup approvals for user1
//             vm.startPrank(user1);
//             IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
//             IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
//             vm.stopPrank();

//             // Setup approvals for user2
//             vm.startPrank(user2);
//             IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
//             IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
//             vm.stopPrank();

//             // Setup approvals for lp
//             vm.startPrank(liquidityProvider);
//             IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
//             IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
//             vm.stopPrank();

//             // Handle superAsset deposits if required
//             if (IRVaultAsset(rVaultAsset).pool_type() == 1) {
//                 vm.prank(user1);
//                 superAsset.deposit(user1, DEPOSIT_AMOUNT);
//                 vm.prank(user2);
//                 superAsset.deposit(user2, DEPOSIT_AMOUNT);
//                 vm.prank(liquidityProvider);
//                 superAsset.deposit(liquidityProvider, DEPOSIT_AMOUNT);
//             }

//             // Initial deposits to RVaultAssets
//             vm.prank(user1);
//             IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user1);
//             vm.prank(user2);
//             IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user2);
//         }
//     }

//     /**
//      * @notice Tests the complete cross-chain withdrawal flow
//      * @dev Verifies deposit setup, withdrawal execution, and cross-chain message handling
//      */
//     function test_lpWithdraw() public {
//         // ======== Test Configuration ========
//         // Setup deposit parameters
//         ChainInfo memory srcChain = supportedChains[0];
//         ChainInfo memory destChain = supportedChains[0];

//         address onBehalfOf = user1;
//         uint16 referralCode = 0;
//         uint256[] memory amounts = new uint256[](1);
//         amounts[0] = 5 ether;

//         uint256[] memory chainIds = new uint256[](1);
//         chainIds[0] = srcChain.chainId;

//         // Set test chain context
//         vm.selectFork(srcChain.forkId);
//         ChainAddresses memory srcChainAddresses = chainAddresses[block.chainid];

//         // ======== Initial Deposit Setup ========
//         // Approve spending
//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.prank(user1);
//             IERC20(underlyingAsset).approve(address(srcChainAddresses.lendingPool), amounts[i]);
//         }

//         // Record events and execute deposit
//         vm.recordLogs();

//         vm.prank(onBehalfOf);
//         chainAddresses[block.chainid].router.deposit(
//             address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds
//         );

//         // ======== Process Deposit Via Relayer ========
//         Identifier[] memory _identifier = new Identifier[](1);
//         bytes[] memory _eventData = new bytes[](1);
//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         uint256[] memory _logindex = new uint256[](1);
//         address originAddress = 0x4200000000000000000000000000000000000023;

//         _logindex[0] = 0;
//         _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);

//         // Decode deposit event data
//         (
//             uint256 _fromChainId,
//             address _sender,
//             address _asset,
//             uint256 _amount,
//             address _onBehalfOf,
//             uint16 _referralCode
//         ) = abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint16));

//         // Prepare and dispatch event
//         bytes32 _selector = CrossChainDeposit.selector;
//         _eventData[0] =
//             abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, _referralCode);

//         // relay the information using relayer calling dispatch function on LendingPool through router
//         vm.recordLogs();
//         console.log('router dispatch');

//         vm.prank(relayer);
//         chainAddresses[block.chainid].router.dispatch(
//             ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex
//         );
//         entries = vm.getRecordedLogs();
//         _eventData[0] = findEventsBySelector(entries, Deposit.selector);
//         console.log('syncing state');

//         for (uint256 i = 0; i < supportedChains.length; i++) {
//             uint256 c_id = supportedChains[i].chainId;
//             uint256 forkId=supportedChains[i].forkId;
//             if (c_id != _fromChainId) {
//                 vm.selectFork(forkId);
//                 _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
//                 vm.prank(relayer);
//                 chainAddresses[block.chainid].router.dispatch(
//                     ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex
//                 );
//             }
//         }

//         // ======== Execute Withdrawal ========
//         // Record events and initiate withdrawal
//         vm.recordLogs();
//         vm.selectFork(destChain.forkId);
//         vm.prank(user1);
//         chainAddresses[block.chainid].router.withdraw(address(underlyingAsset), amounts, user2, destChain.chainId, chainIds);

//         // ======== Process Withdrawal Via Relayer ========
//         _identifier = new Identifier[](1);
//         _eventData = new bytes[](1);
//         entries = vm.getRecordedLogs();
//         _logindex = new uint256[](1);
//         _logindex[0] = 0;

//         _identifier[0] =
//             Identifier(originAddress, block.number, 0, block.timestamp, srcChain.chainId);

//         // Decode withdrawal event data
//         uint256 toChainId;
//         (_fromChainId, _sender, _asset, _amount, _onBehalfOf, toChainId) =
//             abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint256));

//         _selector = CrossChainWithdraw.selector;
//         _eventData[0] =
//             abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, toChainId);

//         // Record and process withdrawal events
//         vm.recordLogs();
//         vm.selectFork(srcChain.forkId);
//         vm.prank(relayer);
//         chainAddresses[srcChain.chainId].router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

//         // ======== Verify Withdrawal Events ========
//         entries = vm.getRecordedLogs();
//         bytes memory eventData = findEventsBySelector(entries, Withdraw.selector);

//         (address user,, address to, uint256 amount,,) =
//             abi.decode(eventData, (address, address, address, uint256, uint256, uint256));

//         // Verify withdrawal parameters
//         assert(user == address(user1));
//         assert(to == address(user2));
//         assert(amount == amounts[0]);

//         /// assert cross chain balances of rtoken and variable debt token

//         // ======== Verify Cross-Chain Messages ========
//         address destRvault=address(chainAddresses[destChain.chainId].rVaultAsset);
//         uint32 remoteEid = (IOAppSetPeer(destRvault).endpoint()).eid();
//         verifyPackets(remoteEid, addressToBytes32(address(destRvault)));

//     }

//     /**
//      * @notice Utility function to locate specific events in the event logs
//      * @param entries Array of event logs to search
//      * @param _selector Event selector to find
//      * @return bytes The event data if found, empty bytes if not found
//      */
//     function findEventsBySelector(Vm.Log[] memory entries, bytes32 _selector) public pure returns (bytes memory) {
//         for (uint256 i = 0; i < entries.length; i++) {
//             if (entries[i].topics[0] == _selector) {
//                 return entries[i].data;
//             }
//         }
//         return bytes("");
//     }
// }
