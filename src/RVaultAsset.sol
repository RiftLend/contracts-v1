// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {ISuperAsset} from "src/interfaces/ISuperAsset.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";
import {ISocket} from "@socket/interfaces/ISocket.sol";
import {IAddressResolver} from "@socket/interfaces/IAddressResolver.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {SuperOwnable} from "src/interop-std/src/auth/SuperOwnable.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {Errors} from "src/libraries/helpers/Errors.sol";
import {PlugBase} from "@socket/base/PlugBase.sol";
import {AppGatewayBase} from "@socket/base/AppGatewayBase.sol";

contract RVaultAsset is Initializable, ERC20, SuperOwnable, PlugBase(address(0)), AppGatewayBase(address(0), address(0)) {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  State Variables                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ILendingPoolAddressesProvider public provider;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint8 public pool_type; // 1 - superchain, unset for ethereum and arbitrum instances
    address public underlying;
    uint256 public withdrawCoolDownPeriod;
    uint256 public maxDepositLimit;

    mapping(address user => uint256 balance) public balances;
    mapping(address => uint256) public _lastWithdrawalTime;
    mapping(address => bool) public isSupportedBungeeTarget;

    uint256[50] __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Events                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CrossChainBridgeUnderlyingSent(bytes txData, uint256 timestamp);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Modifiers                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyRouter() {
        require(provider.getRouter() == msg.sender, Errors.ONLY_ROUTER_CALL);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Constructor                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @param underlying_ - the underlying asset of the rVaultAsset
    /// @param provider_ - the provider of the rVaultAsset
    /// @param name_ - the name of the rVaultAsset
    /// @param symbol_ - the symbol of the rVaultAsset
    /// @param decimals_ - the decimals of the rVaultAsset
    function initialize(
        address underlying_,
        ILendingPoolAddressesProvider provider_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 withdrawCoolDownPeriod_,
        uint256 maxDepositLimit_,
        address _socket,
        address _auctionManager,
        address _addressResolver
    ) external initializer {
        underlying = underlying_;
        provider = provider_;
        pool_type = provider.getPoolType();

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        withdrawCoolDownPeriod = withdrawCoolDownPeriod_;
        maxDepositLimit = maxDepositLimit_;

        _initializeSuperOwner(uint64(block.chainid), msg.sender);
        socket__ = ISocket(_socket);
        auctionManager = _auctionManager;
        isCallSequential = true;
        addressResolver = IAddressResolver(_addressResolver);
    }

    /// @param shares - the amount of shares to mint
    /// @param receiver - the address to which the shares are minted
    function mint(uint256 shares, address receiver) external returns (uint256) {
        return deposit(shares, receiver);
    }

    /// @param assets - the amount of assets to deposit
    /// @param receiver - the address to which the assets are deposited
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        require(totalAssets() + assets <= maxDepositLimit, Errors.DEPOSIT_LIMIT_EXCEEDED);

        balances[receiver] += assets;
        super._mint(receiver, assets);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);

        return assets;
    }

    /// @notice burn shares and send underlying to user if on same chain else bridge underlying to user
    /// @param receiverOfUnderlying - user who is receiving the underlying
    /// @param toChainId - chainId to which the underlying is to be bridged
    /// @param amount - amount of shares to be burned
    function burn(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable {
        if (toChainId != block.chainid) {
            _bridge(receiverOfUnderlying, toChainId, amount);
        } else {
            _burn(msg.sender, amount);
            if (pool_type == 1) {
                ISuperAsset(underlying).withdraw(receiverOfUnderlying, amount);
            } else {
                IERC20(underlying).safeTransfer(receiverOfUnderlying, amount);
            }
        }
    }

    /// @notice withdraws underlying from the rVaultAsset
    /// @param _assets - the amount of underlying to withdraw
    /// @param _receiver - the address to which the underlying is to be sent
    /// @param _owner - the address of the owner of the rVaultAsset
    function withdraw(uint256 _assets, address _receiver, address _owner) public returns (uint256 shares) {
        require(
            block.timestamp - _lastWithdrawalTime[_owner] >= withdrawCoolDownPeriod,
            Errors.WITHDRAW_COOLDOWN_PERIOD_NOT_ELAPSED
        );
        _lastWithdrawalTime[_owner] = block.timestamp;
        shares = _assets;
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares);
        _burn(_owner, shares);
        if (pool_type == 1) ISuperAsset(underlying).withdraw(_receiver, shares);
        else IERC20(underlying).safeTransfer(_receiver, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Bridge underlying                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function bridgeUnderlying(
        address payable _bungeeTarget,
        bytes memory txData,
        address _bungeeAllowanceTarget,
        address _underlying,
        uint256 _underlyingAmount
    ) external onlySuperAdmin {
        require(isSupportedBungeeTarget[_bungeeTarget], Errors.BUNGEE_TARGET_NOT_SUPPORTED);
        if (pool_type == 1) {
            ISuperAsset(_underlying).withdraw(address(this), _underlyingAmount);
        }

        IERC20(_underlying).approve(_bungeeAllowanceTarget, _underlyingAmount);
        (bool success,) = _bungeeTarget.call(txData);
        require(success, Errors.BUNGEE_BRIDGING_FAILED);

        emit CrossChainBridgeUnderlyingSent(txData, block.timestamp);
    }

    /// @notice On receiving side of the bridgeUnderlying call, this function will be called to send the underlying to desired address
    /// @dev the _asset passed cannot be the underlying asset of the rVaultAsset, this function is used cause bungee bridge may sometimes return anySwap or hop tokens that would need manual swapping. https://docs.bungee.exchange/socket-api/guides/bungee-smart-contract-integration#3-destination-contract
    /// @param _asset - asset to be withdrawn
    /// @param _recipient - address to which the underlying is to be sent
    /// @param _amount - amount of underlying to be sent
    function withdrawTokens(address _asset, address _recipient, uint256 _amount) external onlyOwner {
        require(_asset == underlying, Errors.UNAUTHORIZED);
        IERC20(_asset).safeTransfer(_recipient, _amount);
    }

    function setSocket(address newSocket_) external onlyOwner {
        _setSocket(newSocket_);
    }

    function connectSocket(
        address appGateway_,
        address socket_,
        address switchboard_
    ) external onlyOwner {
        // TODO: discuss about ownable ...
        // _claimOwner(socket_);
        _connectSocket(appGateway_, socket_, switchboard_);
    }

    function _sock(address sender, address receiverOfUnderlying, uint256 amount) internal async onlySocket {
        _burn(sender, amount);
        
        uint256 payAmount = amount;
        if (totalAssets() < amount) {
            payAmount = totalAssets();
            _mint(receiverOfUnderlying, amount - payAmount);
        }
        if (pool_type == 1) {
            ISuperAsset(underlying).withdraw(receiverOfUnderlying, payAmount);
        } else {
            IERC20(underlying).safeTransfer(receiverOfUnderlying, payAmount);
        }
    }

    function bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) external payable onlyRouter {
        _bridge(receiverOfUnderlying, toChainId, amount);
    }

    function _bridge(address receiverOfUnderlying, uint256 toChainId, uint256 amount) internal {
        if (toChainId != block.chainid) {
            _sock(msg.sender, receiverOfUnderlying, amount);
        } else {
            _burn(msg.sender, amount);
            if (pool_type == 1) {
                ISuperAsset(underlying).withdraw(receiverOfUnderlying, amount);
            } else {
                IERC20(underlying).safeTransfer(receiverOfUnderlying, amount);
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Privileged Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMaxDepositLimit(uint256 _maxDeposit) public onlySuperAdmin {
        maxDepositLimit = _maxDeposit;
    }
    // set withdrawCoolDownPeriod

    function setWithdrawCoolDownPeriod(uint256 _withdrawCoolDownPeriod) public onlySuperAdmin {
        withdrawCoolDownPeriod = _withdrawCoolDownPeriod;
    }

    // setter for isSupported bungee target ( also a toggler by design)
    function setIsSupportedBungeeTarget(address _target, bool isSupported) public onlySuperAdmin {
        isSupportedBungeeTarget[_target] = isSupported;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20 Functions                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        bool success = super.transfer(recipient, amount);
        if (success) {
            balances[msg.sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override(ERC20) returns (bool) {
        bool success = super.transferFrom(sender, recipient, amount);
        if (success) {
            balances[sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*      ERC4626 Vault compliant functions                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function asset() external view returns (address) {
        return underlying;
    }

    function totalAssets() internal view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    function redeem(uint256 shares, address receiver, address _owner) external returns (uint256 assets) {
        assets = shares;
        withdraw(assets, receiver, _owner);
    }

    // Preview and conversion functions as provided earlier
    function previewMint(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address _owner) external view returns (uint256) {
        return balanceOf(_owner);
    }

    function maxRedeem(address _owner) external view returns (uint256) {
        return balanceOf(_owner);
    }
}
