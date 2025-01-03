// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title ISuperAsset Interface
/// @notice Interface for interacting with the SuperchainAsset contract
interface ISuperAsset {
    /// @notice Get the name of the asset
    /// @return The name of the asset as a string
    function name() external view returns (string memory);

    /// @notice Get the symbol of the asset
    /// @return The symbol of the asset as a string
    function symbol() external view returns (string memory);

    /// @notice Get the number of decimals used by the asset
    /// @return The number of decimals as a uint8
    function decimals() external view returns (uint8);

    /// @notice Mint a specified amount of tokens to a given address
    /// @param to_ The address to mint tokens to
    /// @param amount_ The amount of tokens to mint
    function mint(address to_, uint256 amount_) external;

    /// @notice Burn a specified amount of tokens from a given address
    /// @param to_ The address to burn tokens from
    /// @param amount_ The amount of tokens to burn
    function burn(address to_, uint256 amount_) external;

    /// @notice Transfer tokens to a specified address
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return A boolean indicating whether the operation was successful
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice Transfer tokens from one address to another
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return A boolean indicating whether the operation was successful
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /// @notice Get the underlying asset balance of a user
    /// @param user The address to get the balance of
    /// @return The underlying asset balance of the user
    function balanceOf(address user) external view returns (uint256);

    /// @notice Withdraw tokens sent to the contract
    /// @param _token The address of the token to withdraw
    /// @param _recepient The address to withdraw tokens to
    function withdrawTokens(address _token, address _recepient) external;

    function deposit(address to, uint256 amount) external;
    function withdraw(address to, uint256 amount) external;
}
