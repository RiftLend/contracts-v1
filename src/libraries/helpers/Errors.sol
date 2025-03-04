// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

/**
 * @title Errors library
 * @author Aave
 * @notice Defines the error messages emitted by the different contracts of the Aave protocol
 * @dev Error messages prefix glossary:
 *  - VL = ValidationLogic
 *  - MATH = Math libraries
 *  - CT = Common errors between tokens (RToken, VariableDebtToken and StableDebtToken)
 *  - AT = RToken
 *  - SDT = StableDebtToken
 *  - VDT = VariableDebtToken
 *  - LP = LendingPool
 *  - LPAPR = LendingPoolAddressesProviderRegistry
 *  - LPC = LendingPoolConfiguration
 *  - RL = ReserveLogic
 *  - LPCM = LendingPoolCollateralManager
 *  - P = Pausable
 */
enum CollateralManagerErrors {
    NO_ERROR,
    NO_COLLATERAL_AVAILABLE,
    COLLATERAL_CANNOT_BE_LIQUIDATED,
    CURRRENCY_NOT_BORROWED,
    HEALTH_FACTOR_ABOVE_THRESHOLD,
    NOT_ENOUGH_LIQUIDITY,
    NO_ACTIVE_RESERVE,
    HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD,
    INVALID_EQUAL_ASSETS_TO_SWAP,
    FROZEN_RESERVE
}
//common errors

string constant CALLER_NOT_POOL_ADMIN = "33"; // 'The caller must be the pool admin'
string constant BORROW_ALLOWANCE_NOT_ENOUGH = "59"; // User borrows on behalf, but allowance are too small

//contract specific errors
string constant VL_INVALID_AMOUNT = "1"; // 'Amount must be greater than 0'
string constant VL_NO_ACTIVE_RESERVE = "2"; // 'Action requires an active reserve'
string constant VL_RESERVE_FROZEN = "3"; // 'Action cannot be performed because the reserve is frozen'
string constant VL_CURRENT_AVAILABLE_LIQUIDITY_NOT_ENOUGH = "4"; // 'The current liquidity is not enough'
string constant VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE = "5"; // 'User cannot withdraw more than the available balance'
string constant VL_TRANSFER_NOT_ALLOWED = "6"; // 'Transfer cannot be allowed.'
string constant VL_BORROWING_NOT_ENABLED = "7"; // 'Borrowing is not enabled'
string constant VL_INVALID_INTEREST_RATE_MODE_SELECTED = "8"; // 'Invalid interest rate mode selected'
string constant VL_COLLATERAL_BALANCE_IS_0 = "9"; // 'The collateral balance is 0'
string constant VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = "10"; // 'Health factor is lesser than the liquidation threshold'
string constant VL_COLLATERAL_CANNOT_COVER_NEW_BORROW = "11"; // 'There is not enough collateral to cover a new borrow'
string constant VL_STABLE_BORROWING_NOT_ENABLED = "12"; // stable borrowing not enabled
string constant VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY = "13"; // collateral is (mostly) the same currency that is being borrowed
string constant VL_AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE = "14"; // 'The requested amount is greater than the max loan size in stable rate mode
string constant VL_NO_DEBT_OF_SELECTED_TYPE = "15"; // 'for repayment of stable debt, the user needs to have stable debt, otherwise, he needs to have variable debt'
string constant VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF = "16"; // 'To repay on behalf of an user an explicit amount to repay is needed'
string constant VL_NO_STABLE_RATE_LOAN_IN_RESERVE = "17"; // 'User does not have a stable rate loan in progress on this reserve'
string constant VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE = "18"; // 'User does not have a variable rate loan in progress on this reserve'
string constant VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0 = "19"; // 'The underlying balance needs to be greater than 0'
string constant VL_DEPOSIT_ALREADY_IN_USE = "20"; // 'User deposit is already being used as collateral'
string constant LP_NOT_ENOUGH_STABLE_BORROW_BALANCE = "21"; // 'User does not have any stable rate loan for this reserve'
string constant LP_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET = "22"; // 'Interest rate rebalance conditions were not met'
string constant LP_LIQUIDATION_CALL_FAILED = "23"; // 'Liquidation call failed'
string constant LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW = "24"; // 'There is not enough liquidity available to borrow'
string constant LP_REQUESTED_AMOUNT_TOO_SMALL = "25"; // 'The requested amount is too small for a FlashLoan.'
string constant LP_INCONSISTENT_PROTOCOL_ACTUAL_BALANCE = "26"; // 'The actual balance of the protocol is inconsistent'
string constant LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR = "27"; // 'The caller of the function is not the lending pool configurator'
string constant LP_INCONSISTENT_FLASHLOAN_PARAMS = "28";
string constant CT_CALLER_MUST_BE_LENDING_POOL = "29"; // 'The caller of this function must be a lending pool'
string constant CT_CANNOT_GIVE_ALLOWANCE_TO_HIMSELF = "30"; // 'User cannot give allowance to himself'
string constant CT_TRANSFER_AMOUNT_NOT_GT_0 = "31"; // 'Transferred amount needs to be greater than zero'
string constant RL_RESERVE_ALREADY_INITIALIZED = "32"; // 'Reserve has already been initialized'
string constant LPC_RESERVE_LIQUIDITY_NOT_0 = "34"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_ATOKEN_POOL_ADDRESS = "35"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_STABLE_DEBT_TOKEN_POOL_ADDRESS = "36"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_VARIABLE_DEBT_TOKEN_POOL_ADDRESS = "37"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_STABLE_DEBT_TOKEN_UNDERLYING_ADDRESS = "38"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_VARIABLE_DEBT_TOKEN_UNDERLYING_ADDRESS = "39"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_ADDRESSES_PROVIDER_ID = "40"; // 'The liquidity of the reserve needs to be 0'
string constant LPC_INVALID_CONFIGURATION = "75"; // 'Invalid risk parameters for the reserve'
string constant LPC_CALLER_NOT_EMERGENCY_ADMIN = "76"; // 'The caller must be the emergency admin'
string constant LPAPR_PROVIDER_NOT_REGISTERED = "41"; // 'Provider is not registered'
string constant LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD = "42"; // 'Health factor is not below the threshold'
string constant LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED = "43"; // 'The collateral chosen cannot be liquidated'
string constant LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = "44"; // 'User did not borrow the specified currency'
string constant LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE = "45"; // "There isn't enough liquidity available to liquidate"
string constant LPCM_NO_ERRORS = "46"; // 'No errors'
string constant LP_INVALID_FLASHLOAN_MODE = "47"; //Invalid flashloan mode selected
string constant MATH_MULTIPLICATION_OVERFLOW = "48";
string constant MATH_ADDITION_OVERFLOW = "49";
string constant MATH_DIVISION_BY_ZERO = "50";
string constant RL_LIQUIDITY_INDEX_OVERFLOW = "51"; //  Liquidity index overflows uint128
string constant RL_VARIABLE_BORROW_INDEX_OVERFLOW = "52"; //  Variable borrow index overflows uint128
string constant RL_LIQUIDITY_RATE_OVERFLOW = "53"; //  Liquidity rate overflows uint128
string constant RL_VARIABLE_BORROW_RATE_OVERFLOW = "54"; //  Variable borrow rate overflows uint128
string constant RL_STABLE_BORROW_RATE_OVERFLOW = "55"; //  Stable borrow rate overflows uint128
string constant CT_INVALID_MINT_AMOUNT = "56"; //invalid amount to mint
string constant LP_FAILED_REPAY_WITH_COLLATERAL = "57";
string constant CT_INVALID_BURN_AMOUNT = "58"; //invalid amount to burn
string constant LP_FAILED_COLLATERAL_SWAP = "60";
string constant LP_INVALID_EQUAL_ASSETS_TO_SWAP = "61";
string constant LP_REENTRANCY_NOT_ALLOWED = "62";
string constant LP_CALLER_MUST_BE_AN_RTOKEN = "63";
string constant LP_IS_PAUSED = "64"; // 'Pool is paused'
string constant LP_NO_MORE_RESERVES_ALLOWED = "65";
string constant LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN = "66";
string constant RC_INVALID_LTV = "67";
string constant RC_INVALID_LIQ_THRESHOLD = "68";
string constant RC_INVALID_LIQ_BONUS = "69";
string constant RC_INVALID_DECIMALS = "70";
string constant RC_INVALID_RESERVE_FACTOR = "71";
string constant LPAPR_INVALID_ADDRESSES_PROVIDER_ID = "72";
string constant VL_INCONSISTENT_FLASHLOAN_PARAMS = "73";
string constant LP_INCONSISTENT_PARAMS_LENGTH = "74";
string constant UL_INVALID_INDEX = "77";
string constant LP_NOT_CONTRACT = "78";
string constant SDT_STABLE_DEBT_OVERFLOW = "79";
string constant SDT_BURN_EXCEEDS_BALANCE = "80";
// RVaultAsset-specific errors starting from 81
string constant OFT_SEND_FAILED = "81"; // 'OFT send operation failed'
string constant ONLY_ROUTER_CALL = "82"; // 'Only the router can call this function'
string constant BUNGEE_BRIDGING_FAILED = "83"; // 'Bungee bridging failed'
string constant DEPOSIT_LIMIT_EXCEEDED = "84"; // 'Deposit limit exceeded'
string constant WITHDRAW_COOLDOWN_PERIOD_NOT_ELAPSED = "85"; // 'Withdraw cooldown period has not elapsed'
string constant UNAUTHORIZED = "86"; // 'Unauthorized action'
string constant BUNGEE_TARGET_NOT_SUPPORTED = "87"; // 'Bungee target is not supported'
// Lp Configurator
string constant NOT_PROXY_ADMIN_OWNER = "88";
string constant ZERO_PARAMS = "89";
string constant RVAULT_NOT_FOUND_FOR_ASSET = "90";
string constant ONLY_RELAYER_CALL = "91"; //
string constant LP_FLASHLOAN_FAILED = "92";
string constant BORROW_FAILED = "93";
string constant UPDATE_STATES_FAILED = "94";
string constant ONLY_SELF_CALL = "95";
string constant ONLY_ROUTER_OR_SELF_CALL = "96";
