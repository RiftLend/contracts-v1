// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestDeposit.t.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import {IFlashLoanReceiver} from "src/interfaces/IFlashLoanReceiver.sol";
import {IRToken} from "src/interfaces/IRToken.sol";

import "forge-std/Vm.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";

/*//////////////////////////////////////////////////////////////////////////
                        MAIN TEST CONTRACT DEFINITION
//////////////////////////////////////////////////////////////////////////*/

/**
 * @title LendingPool Flashloan Test Suite
 * @dev Comprehensive test cases for cross-chain flashloan functionality
 * @notice Tests both borrow and repayment scenarios with:
 * - Cross-chain event propagation
 * - State synchronization
 * - Debt position validation
 */
contract LendingPoolTestFlashloan is LendingPoolTestDeposit, IFlashLoanReceiver {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    address asset;
    uint256 mode;
    uint256 amount;
    address receiverAddress;
    address onBehalfOf;
    uint256 chainId;
    bytes32 _selector;
    uint16 referralCode;
    bytes params;
    uint256 premium;
    address target;
    address initiator;
    bool borrowExecuted;
    uint256 totalBorrowedAmount = 0;
    uint256 srcChainId;
    DataTypes.FlashLoanEventParams flashLoanEventParams;
    address rToken;

    function setUp() public override {
        super.setUp();
        deal(address(underlyingAsset), user1, INITIAL_BALANCE);
        // Deal some rVaultAsset to the rToken
        deal(address(underlyingAsset), address(this), INITIAL_BALANCE);
        address _rVaultAsset = proxyLp.getRVaultAssetOrRevert(address(underlyingAsset));
        uint256 pool_type = proxyLp.pool_type();
        if (pool_type == 1) {
            address _superAsset = IRVaultAsset(_rVaultAsset).asset();
            IERC20(address(underlyingAsset)).approve(address(_superAsset), type(uint256).max);
            ISuperAsset(_superAsset).deposit(address(this), INITIAL_BALANCE);
            IERC20(_superAsset).approve(address(_rVaultAsset), type(uint256).max);
        }
        rToken = proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress;
        IRVaultAsset(_rVaultAsset).deposit(INITIAL_BALANCE, address(this));
        IERC20(_rVaultAsset).transfer(rToken, INITIAL_BALANCE / 2);
    }

    function test_lpFlashLoanBorrow() public {
        execute_flashloan(true);
    }

    function test_lpFlashLoanReturn() public {
        execute_flashloan(false);
    }
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CORE FLASHLOAN LOGIC                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Executes flashloan test scenario
     * @param shouldBorrow Determines test mode:
     * - true: Test borrow path and debt accumulation
     * - false: Test repayment path with premium return
     */
    function execute_flashloan(bool shouldBorrow) internal {
        bytes memory eventData;
        bytes[] memory _eventData;
        Identifier[] memory _identifier;
        uint256[] memory _logindex;
        Vm.Log[] memory entries;
        bytes[] memory events;

        test_lpDeposit();

        rToken = proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress;
        // for returning premium
        if (!shouldBorrow) {
            uint256 bal = IERC20(rToken).balanceOf(user1);
            vm.prank(user1);
            IRToken(rToken).transfer(address(this), bal / 4);
        }

        /////////////////////////////////////

        receiverAddress = address(this);
        onBehalfOf = user1;
        DataTypes.FlashloanParams[] memory flashloanParams = new DataTypes.FlashloanParams[](1);
        asset = address(underlyingAsset);
        amount = 10 ether;
        if (shouldBorrow) {
            mode = uint256(DataTypes.InterestRateMode.VARIABLE);
            totalBorrowedAmount += amount;
        } else {
            mode = uint256(DataTypes.InterestRateMode.NONE);
        }
        params = "0x";
        referralCode = 0;
        flashloanParams[0] = DataTypes.FlashloanParams(
            asset, amount, mode, params, referralCode, block.chainid, receiverAddress, onBehalfOf
        );

        vm.recordLogs();
        vm.prank(user1);
        router.initiateFlashLoan(flashloanParams);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                 Processing Cross-Chain Flashloan Event        */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Processing Cross-Chain Flashloan Event ");

        entries = vm.getRecordedLogs();

        _selector = ILendingPool.CrossChainInitiateFlashloan.selector;
        events = EventUtils.findEventsBySelector(entries, _selector);

        _identifier = new Identifier[](events.length);
        _eventData = new bytes[](events.length);
        _logindex = new uint256[](events.length);
        DataTypes.InitiateFlashloanParams memory initiateFlashloanParams;

        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];
            (initiateFlashloanParams) = abi.decode(eventData, (DataTypes.InitiateFlashloanParams));
            _eventData[index] = abi.encode(_selector, initiateFlashloanParams);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*       Dispatch and perform actual Flashloan using relayer     */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Dispatch and perform actual Flashloan using relayer ");
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    Cross-Chain State Sync                   */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        console.log("Cross-Chain State Sync ");
        entries = vm.getRecordedLogs();
        _selector = ILendingPool.FlashLoan.selector;

        events = EventUtils.findEventsBySelector(entries, _selector);
        _identifier = new Identifier[](events.length);
        _eventData = new bytes[](events.length);
        _logindex = new uint256[](events.length);

        console.log("got flashloan events", events.length);
        for (uint256 index = 0; index < events.length; index++) {
            eventData = events[index];
            (flashLoanEventParams) = abi.decode(eventData, (DataTypes.FlashLoanEventParams));
            _eventData[index] = abi.encode(
                _selector,
                flashLoanEventParams.chainId,
                flashLoanEventParams.borrowExecuted,
                flashLoanEventParams.initiator,
                flashLoanEventParams.asset,
                flashLoanEventParams.amount,
                flashLoanEventParams.premium,
                flashLoanEventParams.target,
                flashLoanEventParams.referralCode
            );
        }
        srcChainId = block.chainid;

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (srcChainId != supportedChains[i].chainId) {
                vm.chainId(supportedChains[i].chainId);
                vm.prank(relayer);
                router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
            }
        }

        if (shouldBorrow) {
            /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:°•.°+.*•´°•.°+.*•´*/
            /*     Assert Cross-Chain  Variable Debt Token  Balance is increased for user1 **/
            /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.°•.°+.*•´°•.°+.*•´•*/
            console.log("Assert Cross-Chain  Variable Debt Token  Token Balance ");
            uint256 contract_vdebt_balance = VariableDebtToken(
                address(proxyLp.getReserveData(address(rVaultAsset1)).variableDebtTokenAddress)
            ).crossChainUserBalance(user1);
            console.log(contract_vdebt_balance, totalBorrowedAmount);
            assert(contract_vdebt_balance == totalBorrowedAmount);
        }
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        for (uint256 i = 0; i < assets.length; i++) {
            // just to deal enough assets to return
            assert(IERC20(assets[i]).balanceOf(address(this)) >= amounts[i]);
            deal(assets[i], address(this), amounts[i] + premiums[i]);
            IERC20(assets[i]).approve(msg.sender, amounts[i] + premiums[i]);
        }

        return true;
    }

    function ADDRESSES_PROVIDER() external view returns (ILendingPoolAddressesProvider) {
        return ILendingPoolAddressesProvider(address(lpAddressProvider1));
    }

    function LENDING_POOL() external view returns (ILendingPool) {
        return ILendingPool(address(proxyLp));
    }
}
