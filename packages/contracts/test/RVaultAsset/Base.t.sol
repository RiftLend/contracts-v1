// // SPDX-License-Identifier: agpl-3.0
// pragma solidity 0.8.25;

// import {Test} from "forge-std/Test.sol";
// import {RVaultAsset} from "../../src/RVaultAsset.sol";
// import {TestERC20} from "../utils/TestERC20.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// contract RVaultAssetTest is Test {
//     using SafeERC20 for IERC20;

//     RVaultAsset rVaultAsset;
//     TestERC20 underlyingAsset;
//     address receiver = address(0x2);
//     address spender = address(0x3);
//     address owner = makeAddr("owner");
//     address poolAdmin1 = makeAddr("poolAdmin1");
//     address user1 = makeAddr("user1");
//     address _delegate = makeAddr("_delegate");

//     function setUp() public {
//         // ############## Load deploy config ##############
//         string memory deployConfigPath = vm.envOr("DEPLOY_CONFIG_PATH", string("/configs/deploy-config.toml"));
//         string memory filePath = string.concat(vm.projectRoot(), deployConfigPath);
//         string memory deployConfig = vm.readFile(filePath);

//         // ############## Read deploy config variables ##############
//         string memory chain_a_rpc = vm.parseTomlString(deployConfig, ".forks.chain_a_rpc_url");
//         uint256 chain_a_id = vm.parseTomlUint(deployConfig, ".forks.chain_a_chain_id");
//         address chain_a_cross_l2_prover_address =
//             vm.parseTomlAddress(deployConfig, ".forks.chain_a_cross_l2_prover_address");

//         treasury = vm.parseTomlAddress(deployConfig, ".treasury.address");

//         // ################ Deploy LayerZeroEndpoint ################
//         vm.label(address(lpAddressProvider), "lpAddressProvider");
//         uint32 lzEndpoint_eid = 1;
//         vm.prank(owner);
//         lzEndpoint = new MockLayerZeroEndpointV2(lzEndpoint_eid, owner);

//         // ############## Create Fork to test ##############
//         uint256 _forkId = vm.createSelectFork(chain_a_rpc);
//         uint64 _chainId = uint64(chain_a_id);

//         // ################ Deploy Event validator #################
//         vm.prank(owner);
//         EventValidator eventValidator = new EventValidator((chain_a_cross_l2_prover_address));

//         // ############# Deploy SuperProxyAdmin ####################
//         vm.prank(owner);
//         superProxyAdmin = address(new ProxyAdmin{salt: "superProxyAdmin"}(owner, _chainId));
//         vm.label(superProxyAdmin, "superProxyAdmin");

//         vm.label(address(underlyingAsset), "underlyingAsset");
//         // ################ Mint underlying tokens to users ################
//         vm.prank(owner);
//         underlyingAsset.mint(user1, 1000000 ether);

//         // ################ Deploy LendingPoolAddressesProvider ################
//         bytes32 lp_type = keccak256("OpSuperchain_LENDING_POOL");
//         lpAddressProvider = new LendingPoolAddressesProvider("TUSDC", owner, superProxyAdmin, lp_type);

//         // Deploy the underlying asset (TestERC20)
//         underlyingAsset = new TestERC20("Test USDC", "USDC", 6);
//         vm.label(address(underlyingAsset), "underlyingAsset");

//         // Mint some underlying asset to the owner for testing
//         underlyingAsset.mint(owner, 1000 ether);

//         // Deploy the RVaultAsset contract
//                 // ################ Deploy RVaultAsset ################
//         vm.prank(owner);
//         address rVaultAsset = address(
//             new RVaultAsset{salt: "rVaultAssetImpl"}(
//                 address(underlyingAsset),
//                 ILendingPoolAddressesProvider(address(lpAddressProvider)),
//                 poolAdmin1,
//                 address(lzEndpoint),
//                 _delegate
//             )
//         );

//         vm.label(address(rVaultAsset), "rVaultAsset");

//         // Approve the RVaultAsset contract to spend owner's underlying asset
//         vm.prank(owner);
//         underlyingAsset.approve(address(rVaultAsset), type(uint256).max);
//     }

// }
