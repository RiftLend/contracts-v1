// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Test} from '../../lib/forge-std/src/Test.sol';
import {console} from '../../lib/forge-std/src/console.sol';

import {ILendingPoolAddressesProvider} from '../../src/interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPoolConfigurator} from '../../src/interfaces/ILendingPoolConfigurator.sol';

import {TestERC20} from '../utils/TestERC20.sol';
import {SuperAsset} from '../../src/SuperAsset.sol';
import {RToken} from '../../src/tokenization/RToken.sol';
import {RVaultAsset} from '../../src/RVaultAsset.sol';
import {StableDebtToken} from '../../src/tokenization/StableDebtToken.sol';
import {VariableDebtToken} from '../../src/tokenization/VariableDebtToken.sol';
import {LendingPool} from '../../src/LendingPool.sol';
import {LendingPoolAddressesProvider} from '../../src/configuration/LendingPoolAddressesProvider.sol';
import {LendingPoolConfigurator} from '../../src/LendingPoolConfigurator.sol';
import {DefaultReserveInterestRateStrategy} from '../../src/DefaultReserveInterestRateStrategy.sol';
import {ProxyAdmin} from 'src/interop-std/src/utils/SuperProxyAdmin.sol';
import {OFT} from '@layerzerolabs/oft-evm/contracts/OFT.sol';
import {MockLayerZeroEndpointV2} from '../utils/MockLayerZeroEndpointV2.sol';

import '../../src/interfaces/ISuperAsset.sol';

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
    address rTokenImpl;
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
  address owner = makeAddr('owner');
  address poolAdmin1 = makeAddr('poolAdmin1');
  address router = makeAddr('router');
  address user1 = makeAddr('user1');

  address relayer = makeAddr('relayer');
  address emergencyAdmin = makeAddr('emergencyAdmin');
  address alice = makeAddr('alice');
  address _delegate = makeAddr('_delegate');

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

  function setUp() public {
    uint64 _chainId = 1;

    temps storage t = config[_chainId];

    t.owner = owner;
    t.emergencyAdmin = emergencyAdmin;

    // Deploy underlyingAsset
    underlyingAsset = new TestERC20('TUSDC', 'USDC', 6);
    vm.label(address(underlyingAsset), 'underlyingAsset');

    // Mint underlying to user1
    underlyingAsset.mint(user1, 100 ether);

    // Deploy SuperProxyAdmin
    superProxyAdmin = address(
      new ProxyAdmin{salt: 'superProxyAdmin'}(owner, _chainId)
    );
    vm.label(superProxyAdmin, 'superProxyAdmin');
    t.proxyAdmin = superProxyAdmin;

    // Deploy implementations
    address rTokenImpl = address(new RToken{salt: 'rTokenImpl'}());

    address rVaultAsset = address(
      new RVaultAsset{salt: 'rVaultAssetImpl'}(
        address(underlyingAsset),
        ILendingPoolAddressesProvider(address(lpAddressProvider)),
        poolAdmin1,
        address(lzEndpoint)
      )
    );

    address stableDebtTokenImpl = address(
      new StableDebtToken{salt: 'stableDebtTokenImpl'}()
    );
    address variableDebtTokenImpl = address(
      new VariableDebtToken{salt: 'variableDebtTokenImpl'}()
    );
    implementationLp = new LendingPool();
    vm.label(address(implementationLp), 'implementationLp');

    // Deploy LendingPoolAddressesProvider
    bytes32 lp_type = keccak256('OpSuperchain_LENDING_POOL');
    lpAddressProvider = new LendingPoolAddressesProvider(
      'TUSDC',
      owner,
      t.proxyAdmin,
      lp_type
    );
    vm.label(address(lpAddressProvider), 'lpAddressProvider');
    uint32 lzEndpoint_eid = 1;
    lzEndpoint = new MockLayerZeroEndpointV2(lzEndpoint_eid, owner);

    // Deploy SuperAsset
    console.log('yes');
    vm.prank(owner);

    superAsset = new SuperAsset(
      address(underlyingAsset),
      address(lzEndpoint),
      _delegate
    );
    // Deploy proxy LendingPool
    vm.prank(owner);
    lpAddressProvider.setLendingPoolImpl(address(implementationLp));
    proxyLp = LendingPool(lpAddressProvider.getLendingPool());
    vm.label(address(proxyLp), 'proxyLp');

    // Set settings in addressProvider
    vm.prank(owner);
    lpAddressProvider.setPoolAdmin(poolAdmin1);

    vm.prank(owner);
    lpAddressProvider.setRelayer(relayer);

    vm.prank(owner);
    lpAddressProvider.setRouter(router);
    vm.prank(owner);
    lpAddressProvider.setRVaultAsset(rTokenImpl);

    // Deploy LendingPoolConfigurator
    lpConfigurator = new LendingPoolConfigurator();

    // Deploy proxy configurator
    vm.prank(owner);
    lpAddressProvider.setLendingPoolConfiguratorImpl(address(lpConfigurator));
    proxyConfigurator = LendingPoolConfigurator(
      lpAddressProvider.getLendingPoolConfigurator()
    );

    // Activate Reserves
    vm.prank(poolAdmin1);
    proxyConfigurator.activateReserve(address(underlyingAsset));
    vm.prank(poolAdmin1);
    proxyConfigurator.activateReserve(address(superAsset));
    vm.prank(poolAdmin1);
    proxyConfigurator.activateReserve(address(rVaultAsset));

    // vm.prank(owner);
    // proxyConfigurator.activateReserve(address(superAsset));

    // Deploy DefaultReserveInterestRateStrategy
    address strategy = address(
      new DefaultReserveInterestRateStrategy(
        ILendingPoolAddressesProvider(address(lpAddressProvider)),
        0.8 * 1e27, // optimalUtilizationRate
        0.02 * 1e27, // baseVariableBorrowRate
        0.04 * 1e27, // variableRateSlope1
        0.75 * 1e27, // variableRateSlope2
        0.02 * 1e27, // stableRateSlope1
        0.75 * 1e27 // stableRateSlope2
      )
    );
    vm.label(strategy, 'DefaultReserveInterestRateStrategy');

    // Initialize reserve
    ILendingPoolConfigurator.InitReserveInput[]
      memory input = new ILendingPoolConfigurator.InitReserveInput[](1);
    input[0].rTokenImpl = address(rTokenImpl);
    input[0].stableDebtTokenImpl = address(stableDebtTokenImpl);
    input[0].variableDebtTokenImpl = address(variableDebtTokenImpl);
    input[0].underlyingAssetDecimals = 6;
    input[0].interestRateStrategyAddress = strategy;
    input[0].underlyingAsset = address(underlyingAsset);
    input[0].treasury = vm.addr(35);
    input[0].incentivesController = vm.addr(17);
    input[0].superAsset = address(superAsset);
    input[0].underlyingAssetName = 'Mock USDC';
    input[0].rTokenName = 'aToken-TUSDC';
    input[0].rTokenSymbol = 'aTUSDC';
    input[0].variableDebtTokenName = 'vDebt';
    input[0].variableDebtTokenSymbol = 'vDBT';
    input[0].stableDebtTokenName = 'vStable';
    input[0].stableDebtTokenSymbol = 'vSBT';
    input[0].params = 'v';
    input[0].salt = 'salt';
    vm.prank(poolAdmin1);
    proxyConfigurator.batchInitReserve(input);
  }

  function testDeposit() public {
    // act
    address asset = address(underlyingAsset);
    uint256[1] memory amounts;
    amounts[0] = 10 ether;
    address onBehalfOf = user1;
    uint16 referralCode = 0;
    uint16[1] memory chainIds;
    chainIds[0] = 1;
    vm.prank(onBehalfOf);
    underlyingAsset.approve(address(proxyLp), amounts[0]);

    vm.prank(router);
    proxyLp.deposit(onBehalfOf, asset, amounts[0], onBehalfOf, referralCode);

    // assert
    // 1. superchainAsset
    address aToken_ = proxyLp.getReserveData(asset).rTokenAddress;

    assertEq(superAsset.balanceOf(aToken_), 1000);

    // 2. aToken
    // assertEq((aToken).balanceOf(alice), 1000);
    // assertEq((aToken).balanceOf(treasury), 10);
  }
}
