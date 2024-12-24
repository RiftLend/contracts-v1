// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;


interface IRVaultAsset {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function underlying() external view returns (address);
    function balances(address user) external view returns (uint256);
    function totalBalances() external view returns (uint256);
    function provider() external view returns (address);
    function mint(address to_, uint256 amount_) external;
    function burn(address to_, uint256 amount_) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function bridgeUnderlying(address payable _to, bytes memory txData, address _allowanceTarget, uint256 _amount) external;
    function withdrawTokens(address _token, address _recepient) external;
    function version() external pure returns (string memory);
}
