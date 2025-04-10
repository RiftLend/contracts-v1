// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IVariableDebtToken} from "../interfaces/IVariableDebtToken.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IAaveIncentivesController} from "../interfaces/IAaveIncentivesController.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {CT_INVALID_MINT_AMOUNT, ONLY_ROUTER_CALL, CT_INVALID_BURN_AMOUNT} from "../libraries/helpers/Errors.sol";
import {DebtTokenBase} from "./base/DebtTokenBase.sol";

/**
 * @title VariableDebtToken
 * @notice Implements a variable debt token to track the borrowing positions of users
 * at variable rate mode
 * @author Aave
 *
 */
contract VariableDebtToken is DebtTokenBase, IVariableDebtToken {
    using WadRayMath for uint256;

    uint256 public constant DEBT_TOKEN_REVISION = 0x1;

    ILendingPool internal _pool;
    address internal _underlyingAsset; // _underlyingAsset=RVaultAsset
    IAaveIncentivesController internal _incentivesController;
    ILendingPoolAddressesProvider internal _addressesProvider;

    modifier onlyRouter() {
        require(_addressesProvider.getRouter() == msg.sender, ONLY_ROUTER_CALL);
        _;
    }

    /**
     * @dev Initializes the debt token.
     * @param pool The address of the lending pool where this rToken will be used
     * @param underlyingAsset The address of the underlying asset of this rToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
     * @param debtTokenName The name of the token
     * @param debtTokenSymbol The symbol of the token
     */
    function initialize(
        ILendingPool pool,
        address underlyingAsset,
        IAaveIncentivesController incentivesController,
        ILendingPoolAddressesProvider addressesProvider,
        uint8 debtTokenDecimals,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) public override initializer {
        _setName(debtTokenName);
        _setSymbol(debtTokenSymbol);
        _setDecimals(debtTokenDecimals);

        _pool = pool;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;
        _addressesProvider = addressesProvider;

        emit Initialized(
            underlyingAsset,
            address(pool),
            address(incentivesController),
            debtTokenDecimals,
            debtTokenName,
            debtTokenSymbol,
            params
        );
    }

    /**
     * @dev Gets the revision of the stable debt token implementation
     * @return The debt token implementation revision
     *
     */
    function getRevision() internal pure virtual returns (uint256) {
        return DEBT_TOKEN_REVISION;
    }

    /**
     * @dev Calculates the accumulated debt balance of the user
     * @return The debt balance of the user
     *
     */
    function balanceOf(address user) public view virtual override returns (uint256) {
        uint256 scaledBalance = super.balanceOf(user);

        if (scaledBalance == 0) {
            return 0;
        }

        return scaledBalance.rayMul(_pool.getReserveNormalizedVariableDebt(_underlyingAsset));
    }

    /**
     * @dev Updates the cross chain balance
     * @param amountScaled The amount scaled
     * @param mode The mode
     */
    function updateCrossChainBalance(address user, uint256 amountScaled, uint256 mode) external override onlyRouter {
        if (mode == 1) {
            crossChainUserBalance[user] += amountScaled;
            _totalCrossChainSupply += amountScaled;
        } else if (mode == 2) {
            _totalCrossChainSupply -= amountScaled;
            crossChainUserBalance[user] -= amountScaled;
        }
    }

    /**
     * @dev Mints debt token to the `onBehalfOf` address
     * -  Only callable by the LendingPool
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     * of credit delegate, or same as `onBehalfOf` otherwise
     * @param onBehalfOf The address receiving the debt tokens
     * @param amount The amount of debt being minted
     * @param index The variable debt index of the reserve
     * @return `true` if the the previous balance of the user is 0
     *
     */
    function mint(address user, address onBehalfOf, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (bool, uint256, uint256)
    {
        if (user != onBehalfOf) {
            _decreaseBorrowAllowance(onBehalfOf, user, amount);
        }

        uint256 previousBalance = super.balanceOf(onBehalfOf);
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, CT_INVALID_MINT_AMOUNT);

        _mint(onBehalfOf, amountScaled);

        emit Transfer(address(0), onBehalfOf, amount);
        emit Mint(user, onBehalfOf, amount, index);

        return (previousBalance == 0, 1, amountScaled);
    }

    /**
     * @dev Burns user variable debt
     * - Only callable by the LendingPool
     * @param user The user whose debt is getting burned
     * @param amount The amount getting burned
     * @param index The variable debt index of the reserve
     *
     */
    function burn(address user, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (uint256, uint256)
    {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, CT_INVALID_BURN_AMOUNT);

        _burn(user, amountScaled);

        emit Transfer(user, address(0), amount);
        emit Burn(user, amount, index);

        return (2, amountScaled);
    }

    /**
     * @dev Returns the principal debt balance of the user from
     * @return The debt balance of the user since the last burn/mint action
     *
     */
    function scaledBalanceOf(address user) public view virtual override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the total supply of the variable debt token. Represents the total debt accrued by the users
     * @return The total supply
     *
     */
    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply().rayMul(_pool.getReserveNormalizedVariableDebt(_underlyingAsset));
    }

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return the scaled total supply
     *
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    function crossChainScaledTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    function getCrossChainUserBalance(address user) external view returns (uint256) {
        return crossChainUserBalance[user];
    }

    /**
     * @dev Returns the principal balance of the user and principal total supply.
     * @param user The address of the user
     * @return The principal balance of the user
     * @return The principal total supply
     *
     */
    function getScaledUserBalanceAndSupply(address user) external view override returns (uint256, uint256) {
        return (super.balanceOf(user), super.totalSupply());
    }

    /**
     * @dev Returns the address of the underlying asset of this rToken (E.g. WETH for aWETH)
     *
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the incentives controller contract
     *
     */
    function getIncentivesController() external view override returns (IAaveIncentivesController) {
        return _getIncentivesController();
    }

    /**
     * @dev Returns the address of the lending pool where this rToken is used
     *
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    function _getIncentivesController() internal view override returns (IAaveIncentivesController) {
        return _incentivesController;
    }

    function _getUnderlyingAssetAddress() internal view override returns (address) {
        return _underlyingAsset;
    }

    function _getLendingPool() internal view override returns (ILendingPool) {
        return _pool;
    }
}
