// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IRVaultAsset} from "src/interfaces/IRVaultAsset.sol";
import {IOFT} from "src/libraries/helpers/layerzero/IOFT.sol";

import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {UserConfiguration} from "src/libraries/configuration/UserConfiguration.sol";
import {Identifier} from "src/libraries/EventValidator.sol";
import {Origin, MessagingReceipt} from "src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";

import {CrossChainDeposit, CrossChainWithdraw} from "src/interfaces/ILendingPool.sol";
import {ValidationMode} from "src/libraries/EventValidator.sol";
import {LendingPoolTestDeposit} from "./LendingPoolTestDeposit.t.sol";

import {RVaultAsset} from "src/RVaultAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";

contract LendingPoolTestWithdraw is LendingPoolTestDeposit {
    RVaultAsset aRVaultAsset;
    RVaultAsset bRVaultAsset;
    uint32 private aEid = 1;
    uint32 private bEid = 2;

    function setUp() public virtual override {
        super.setUp();
        // Provide initial Ether balances to users for testing purposes
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);

        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();

        // Initialize 2 endpoints, using UltraLightNode as the library type
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy two instances of RVaultAsset for testing, associating them with respective endpoints
        aRVaultAsset = RVaultAsset(
            _deployOApp(
                type(RVaultAsset).creationCode,
                abi.encode(
                    address(superAsset),
                    ILendingPoolAddressesProvider(address(lpAddressProvider1)),
                    address(lzEndpoint),
                    _delegate,
                    rVaultAssetTokenName1,
                    rVaultAssetTokenSymbol1,
                    underlyingAssetDecimals
                )
            )
        );
        bRVaultAsset = RVaultAsset(
            _deployOApp(
                type(RVaultAsset).creationCode,
                abi.encode(
                    address(superAsset),
                    ILendingPoolAddressesProvider(address(lpAddressProvider1)),
                    address(lzEndpoint),
                    _delegate,
                    rVaultAssetTokenName2,
                    rVaultAssetTokenSymbol2,
                    underlyingAssetDecimals
                )
            )
        );

        // Configure and wire the OFTs together
        address[] memory ofts = new address[](2);
        ofts[0] = address(aRVaultAsset);
        ofts[1] = address(bRVaultAsset);
        this.wireOApps(ofts);

        // Mint initial tokens for user1 and user2
        for (uint256 i = 0; i < ofts.length; i++) {
            address rVaultAsset = ofts[i];

            // Fund accounts with underlying token
            deal(address(underlyingAsset), user1, INITIAL_BALANCE);
            deal(address(underlyingAsset), user2, INITIAL_BALANCE);
            // Approve rVaultAsset to spend underlying tokens
            vm.startPrank(user1);
            IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
            IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
            vm.stopPrank();

            vm.startPrank(user2);
            IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
            IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
            vm.stopPrank();

            // Get superAssets
            if (IRVaultAsset(rVaultAsset).pool_type() == 1) {
                vm.prank(user1);
                superAsset.deposit(user1, DEPOSIT_AMOUNT);
                vm.prank(user2);
                superAsset.deposit(user2, DEPOSIT_AMOUNT);
            }

            // Get rVaultAssets
            vm.prank(user1);
            IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user1);
            vm.prank(user2);
            IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user2);
        }
    }

    function test_lpWithdraw() public {
        // ########### Deposit  ###########
        // ########### Prepare deposit params
        uint256[] memory amounts;
        address onBehalfOf;
        uint16 referralCode;
        uint256[] memory chainIds;

        amounts = new uint256[](1);
        amounts[0] = 5 ether;
        onBehalfOf = user1;
        referralCode = 0;
        chainIds = new uint256[](1);
        chainIds[1] = bEid;

        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);

        // ########### Deposit through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.deposit(address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds);

        // ####### Relayer ########

        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );

        (
            uint256 _fromChainId,
            address _sender,
            address _asset,
            uint256 _amount,
            address _onBehalfOf,
            uint16 _referralCode
        ) = abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint16));
        bytes32 _selector = CrossChainDeposit.selector;

        _eventData[0] =
            abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, _referralCode);

        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
        ////////////////////////

        //// ############ Ensure deposit was successful
        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(address(aRVaultAsset));
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(address(aRVaultAsset)).balanceOf(rToken), amounts[0]);
        //////////////////////////////////

        // ########### Withdraw ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.withdraw(address(underlyingAsset), amounts, onBehalfOf, block.chainid, chainIds);
        // console.log("withdraw success");

        // ############# Relayer ##########
        _identifier = new Identifier[](1);
        _eventData = new bytes[](1);
        entries = vm.getRecordedLogs();
        _logindex = new uint256[](1);
        _logindex[0] = 0;
        address originAddress = address(0x4200000000000000000000000000000000000023);

        _identifier[0] = Identifier(originAddress, block.number, 0, block.timestamp, block.chainid);
        // event CrossChainWithdraw( uint256 fromChainId, address sender, address asset, uint256 amount, address to, uint256 toChainId);
        uint256 toChainId;
        (_fromChainId, _sender, _asset, _amount, _onBehalfOf, toChainId) =
            abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint256));
        _selector = CrossChainWithdraw.selector;

        _eventData[0] =
            abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, toChainId);

        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        // Verify that the packets were correctly sent to the destination chain.
        // @param _dstEid The endpoint ID of the destination chain.
        // @param _dstAddress The OApp address on the destination chain.
        verifyPackets(bEid, addressToBytes32(address(bRVaultAsset)));

        // Set up parameters for the composed message
        // uint32 dstEid_ = bEid;
        // address from_ = address(bOFT);
        // bytes memory options_ = options;
        // bytes32 guid_ = msgReceipt.guid;
        // address to_ = address(composer);

        // bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
        //     msgReceipt.nonce,
        //     aEid,
        //     _amount,
        //     abi.encodePacked(addressToBytes32(user1), composeMsg)
        // );

        // Execute the composed message
        // this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);
        // vm.startPrank(address(lzEndpoint));
        // aRVaultAsset.lzReceive(
        //     _origin, guid, abi.encode(onBehalfOf, amountReceivedLD), address(lzEndpoint), bytes("")
        // );
        // vm.stopPrank();

        ///////////////////////////////////////////////
        // On the destination chain , the executor picks up the emitted logs ,
        // decodes the packet  and initiate a call to lzReceive on destination address on destination chain

        // // Getting the emitted logs of interest out of all
        // entries = vm.getRecordedLogs();
        // bytes memory oftSentLogData = findEventBySelector(entries, IOFT.OFTSent.selector);

        // // event OFTSent(bytes32  guid,uint32 dstEid,address  fromAddress,uint256 amountSentLD,uint256 amountReceivedLD);
        // (bytes32 guid, uint32 dstEid,,, uint256 amountReceivedLD) =
        //     abi.decode(oftSentLogData, (bytes32, uint32, address, uint256, uint256));
        // // console.log("decoded oftsent");

        // // Building a packet from logs and passing it to lzReceive
        // Origin memory _origin = Origin(uint32(_fromChainId), bytes32(uint256(uint160(address(lzEndpoint)))), 1);
        // vm.chainId(dstEid);
        // // funds are credited to aRVaultAsset by bridge logic
        // deal(address(superAsset), address(aRVaultAsset), amountReceivedLD);
        // vm.startPrank(address(lzEndpoint));
        // aRVaultAsset.lzReceive(
        //     _origin, guid, abi.encode(onBehalfOf, amountReceivedLD), address(lzEndpoint), bytes("")
        // );
        // vm.stopPrank();

        // DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(aRVaultAsset);
        // address rToken = reserveData.rTokenAddress;

        // assertEq(IERC20(aRVaultAsset).balanceOf(rToken), amounts[0]);
    }

    function findEventBySelector(Vm.Log[] memory entries, bytes32 _selector) public pure returns (bytes memory) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == _selector) {
                return entries[i].data;
            }
        }
        return bytes("");
    }
}
