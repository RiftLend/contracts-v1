// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;
import {IFlashLoanReceiver} from "src/interfaces/IFlashLoanReceiver.sol";

library DataTypes {


    // ILendingPool structs

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
        address currentrTokenAddress;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address debtToken;
    }

    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 sendToChainId;
        uint256 amount;
        address rVaultAsset;
        address rTokenAddress;
        uint16 referralCode;
        bool releaseUnderlying;
    }

    /**
     * @dev Emitted on deposit()
     * @param user The address initiating the deposit
     * @param reserve The address of the underlying asset of the reserve
     * @param amount The amount deposited
     * @param onBehalfOf The beneficiary of the deposit, receiving the rTokens
     * @param referral The referral code used
     * @param mintMode The mint mode: 0 for rTokens, 1 for minting, 2 for burning
     * @param amountScaled The amount scaled to the pool's unit
     *
     */
    struct DepositEventParams {
        address user;
        address reserve;
        uint256 amount;
        address onBehalfOf;
        uint16 referral;
        uint256 mintMode;
        uint256 amountScaled;
    }
    /**
     * @param user The address initiating the withdrawal, owner of rTokens
     * @param reserve The address of the underlyng asset being withdrawn
     * @param to Address that will receive the underlying
     * @param amount The amount to be withdrawn
     * @param mode The mode: 0 for rTokens, 1 for minting, 2 for burning
     * @param amountScaled The amount scaled to the pool's unit
    */
    struct WithdrawEventParams {
        address user;
        address reserve;
        address to;
        uint256 amount;
        uint256 mode;
        uint256 amountScaled;
    }

 /**
     * @param reserve The address of the underlying asset being borrowed
     * @param amount The amount borrowed out
     * @param user The address of the user initiating the borrow(), receiving the funds on borrow() or just
     * initiator of the transaction on flashLoan()
     * @param onBehalfOf The address that will be getting the debt
     * @param sendToChainId The chain id to send the funds to
     * @param borrowRate The numeric rate at which the user has borrowed
     * @param mintMode 0 if minting rTokens, 1 if minting stable debt, 2 if minting variable debt
     * @param amountScaled The amount scaled to the pool's unit
     * @param referral The referral code used
     *
     */
    struct BorrowEventParams {
        address reserve;
        uint256 amount;
        address user;
        address onBehalfOf;
        uint256 sendToChainId;
        uint256 borrowRate;
        uint256 mintMode;
        uint256 amountScaled;
        uint16 referral;
    }
    
    /**
     * @dev Emitted on repay()
     * @param reserve The address of the underlying asset of the reserve
     * @param amount The amount repaid
     * @param user The beneficiary of the repayment, getting his debt reduced
     * @param repayer The address of the user initiating the repay(), providing the funds
     * @param mode 1 if minting, 2 if burning
     * @param amountBurned The amount of debt being burned
     *
     */
    struct RepayEventParams {
        address reserve;
        uint256 amount;
        address user;
        address repayer;
        uint256 mode;
        uint256 amountBurned;
    }

    /**
     * @param chainId The chain id
     * @param borrowExecuted Whether the borrow was executed
     * @param initiator The address initiating the flash loan
     * @param asset The address of the asset being flash borrowed
     * @param amount The amount flash borrowed
     * @param premium The fee flash borrowed
     * @param target The address of the flash loan receiver contract
     * @param referralCode The referral code used
     *
     */
    struct FlashLoanEventParams {
        uint256 chainId;
        bool borrowExecuted;
        address initiator;
        address asset;
        uint256 amount;
        uint256 premium;
        address target;
        uint16 referralCode;
    }

    // Structs for cross-chain events
    struct CrosschainDepositData {
        uint256 fromChainId;
        address sender;
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint16 referralCode;
    }

    struct CrosschainLiquidationCallData {
        uint256 chainId;
        address sender;
        address collateralAsset;
        address debtAsset;
        address user;
        uint256 debtToCover;
        bool receiveRToken;
    }

    struct CrosschainBorrowData {
        uint256 borrowFromChainId;
        uint256 sendToChainId;
        address sender;
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint16 referralCode;
    }

    struct CrosschainWithdrawData {
        uint256 fromChainId;
        address sender;
        address asset;
        uint256 amount;
        address to;
        uint256 toChainId;
    }

    struct CrosschainRepayData {
        uint256 fundChainId;
        address sender;
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint256 debtChainId;
    }

    struct CrosschainRepayFinalizeData {
        uint256 debtChainId;
        address sender;
        address onBehalfOf;
        uint256 amount;
        address asset;
    }

    ///////////////////////
    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        address rTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
        address superAsset;
    }

    enum Action_type {
        DEPOSIT,
        WITHDRAW,
        BORROW,
        TRANSFER,
        REPAY,
        LIQUIDATION,
        SET_USER_RESERVE_AS_COLLATERAL
    }

    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct UserConfigurationMap {
        uint256 data;
    }

    enum InterestRateMode {
        NONE,
        VARIABLE
    }

    struct BungeeBridgeOrder {
        bytes32 id;
        // 0 for INIT - initiated
        // 1 for PENDING - sent order from source chain
        // 2 for EXECUTED received at destination chain and funds transferred
        uint8 status;
        address user;
        address receiver;
        uint256 srcChainId;
        uint256 destChainId;
        uint256 timestamp;
        uint256 amount;
    }

    struct RepayParam {
        uint256 fundChainId;
        uint256 debtChainId;
        uint256 amount;
    }

    struct FlashloanParams {
        address asset;
        uint256 amount;
        uint256 mode;
        bytes params;
        uint16 referralCode;
        uint256 chainid;
        address receiverAddress;
        address onBehalfOf;
    }

    struct InitiateFlashloanParams {
        address sender;
        FlashloanParams flashloanParams;
    }
}
