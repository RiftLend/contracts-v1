// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBase.t.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";

/*´:°•.°+.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°+.•´.:*/
/*        Lending Pool Deposit Functions               */
/*´:°•.°+.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°+.•´.:*/

contract LendingPoolTestDeposit is LendingPoolTestBase {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    struct DepositLocalVars {
        bytes[] _eventData;
        uint256[] amounts;
        uint256[] chainIds;
        address onBehalfOf;
        uint16 referralCode;
        address rToken;
        bytes32 selector;
        DataTypes.CrosschainDepositData crosschainDepositParams;
        DataTypes.DepositEventParams depositParams;
        DataTypes.UserConfigurationMap userConfig;
        DataTypes.ReserveData reserveData;
        bytes eventData;
    }

    DepositLocalVars depositLocalVars;

    function test_lpDeposit() public {
        super.setUp();

        Identifier[] memory _identifier;
        uint256[] memory _logindex;
        Vm.Log[] memory entries;

        _identifier = new Identifier[](1);
        _logindex = new uint256[](1);
        depositLocalVars._eventData = new bytes[](1);

        // ########### Prepare deposit params
        (
            depositLocalVars.amounts,
            depositLocalVars.onBehalfOf,
            depositLocalVars.referralCode,
            depositLocalVars.chainIds
        ) = getActionXConfig();

        vm.prank(user1);
        underlyingAsset.approve(address(proxyLp), depositLocalVars.amounts[0]);

        // ########### Deposit through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.deposit(
            address(underlyingAsset),
            depositLocalVars.amounts,
            depositLocalVars.onBehalfOf,
            depositLocalVars.referralCode,
            depositLocalVars.chainIds
        );
        entries = vm.getRecordedLogs();

        console.log("preparing relayer deposit dispatch");
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );

        (depositLocalVars.crosschainDepositParams) = abi.decode(entries[0].data, (DataTypes.CrosschainDepositData));
        depositLocalVars.selector = ILendingPool.CrossChainDeposit.selector;

        depositLocalVars._eventData[0] = abi.encode(
            depositLocalVars.selector,
            depositLocalVars.crosschainDepositParams.fromChainId,
            depositLocalVars.crosschainDepositParams.sender,
            depositLocalVars.crosschainDepositParams.asset,
            depositLocalVars.crosschainDepositParams.amount,
            depositLocalVars.crosschainDepositParams.onBehalfOf,
            depositLocalVars.crosschainDepositParams.referralCode
        );
        // deposit dispatch and perform actual lp.deposit
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, depositLocalVars._eventData, bytes(""), _logindex);
        //
        depositLocalVars.reserveData = proxyLp.getReserveData(rVaultAsset1);
        depositLocalVars.rToken = depositLocalVars.reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(depositLocalVars.rToken), depositLocalVars.amounts[0]);

        depositLocalVars.userConfig = proxyLp.getUserConfiguration(depositLocalVars.crosschainDepositParams.onBehalfOf);
        assert(depositLocalVars.userConfig.isUsingAsCollateralOrBorrowing(depositLocalVars.reserveData.id) == true);
        // sync deposit states across other chains

        entries = vm.getRecordedLogs();
        depositLocalVars.eventData = EventUtils.findEventsBySelector(entries, ILendingPool.Deposit.selector)[0];

        (depositLocalVars.depositParams) = abi.decode(depositLocalVars.eventData, (DataTypes.DepositEventParams));

        depositLocalVars._eventData[0] = abi.encode(
            ILendingPool.Deposit.selector,
            depositLocalVars.depositParams.user,
            depositLocalVars.depositParams.reserve,
            depositLocalVars.depositParams.amount,
            depositLocalVars.depositParams.onBehalfOf,
            depositLocalVars.depositParams.referral,
            depositLocalVars.depositParams.mintMode,
            depositLocalVars.depositParams.amountScaled
        );
        // sync state of deposit for updating crosschain balances
        console.log("sync state of deposit for updating crosschain balances");
        vm.chainId(supportedChains[1].chainId);
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, depositLocalVars._eventData, bytes(""), _logindex);

        /// assert cross chain balances of rtoken
        assert(
            RToken(payable(proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress)).totalCrosschainUnderlyingAssets(
            ) == depositLocalVars.depositParams.amount
        );
    }

    function getActionXConfig()
        public
        view
        returns (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds)
    {
        amounts = new uint256[](1);
        amounts[0] = DEPOSIT_AMOUNT;
        onBehalfOf = user1;
        referralCode = 0;
        chainIds = new uint256[](1);
        chainIds[0] = supportedChains[0].chainId;
    }
}
