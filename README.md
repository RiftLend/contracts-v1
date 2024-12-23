# Introduction

RiftLend is a revolutionary new lending and borrowing protocol native to the OP super-chain ecosystem, enabling seamless cross-chain lending and borrowing across all supported L2 networks. By leveraging the power of interop's, RiftLend eliminates traditional barriers between chains, creating a unified liquidity landscape.

Based on the battle-tested Aave V2 architecture, RiftLend introduces innovations to fully embrace the superchain paradigm, eliminating the need for isolated protocol instances across chains. Our protocol abstracts chain-specific complexities to deliver a seamless, CEX-like experience featuring:

- Unified interest rates across all supported L2 chains
- Chain-agnostic lending and borrowing capabilities
- Seamless crosschain asset management
- Native superchain asset support

Users can freely lend assets from any supported chain and borrow on their preferred destination chain without managing complex cross-chain interactions or dealing with fragmented liquidity pools.

## Key Features

- **Cross-Chain Interoperability**: Native integration with OP Stack interop for seamless cross-chain operations
- **Capital Efficiency**: Unified liquidity pools across L2s minimize fragmentation
- **Battle-Tested Foundation**: Built on Aave V2's proven architecture
- **User Experience**: CEX-like simplicity for cross-chain lending/borrowing

## Architecture Overview

### Core Components

- **Markets**: Each supported asset (e.g. USDC, UNI) has a dedicated LendingPool instance that manages all lending/borrowing activity for that asset across all supported L2 chains
- **Proxy Pattern**: All LendingPools operate behind upgradeable proxies, allowing protocol improvements while preserving user balances and state
- **Address Management**: LendingPoolAddressesProvider acts as the central registry and factory, managing protocol component addresses and cross-chain communication
- **Governance**: Protocol governance will maintain ownership of LendingPoolAddressesProvider to coordinate protocol-wide updates and risk parameters

### Primary Features

The LendingPool contract serves as the main interaction point for users, offering:

- **Cross-Chain Deposits/Withdrawals**: Deposit assets on any chain and withdraw on another
- **Unified Borrowing**: Borrow against your deposits across all supported chains
- **Dynamic Rate Management**: Switch between variable and stable interest rates
- **Flexible Collateral**: Enable/disable assets as collateral across chains
- **Risk Management**: Liquidation mechanism to maintain protocol solvency
- **Flash Loans**: Single-transaction uncollateralized loans for arbitrage/refinancing
- **Superchain Asset Support**: Native integration with OP Stack bridged assets

The LendingPool contract provides the following core functionalities:

```solidity
/**
 * Main interaction point for users:
 * - Deposit assets
 * - Withdraw assets
 * - Borrow against collateral
 * - Repay loans
 * - Toggle between variable/stable rates
 * - Manage collateral settings
 * - Execute liquidations
 * - Perform flash loans
 */
```

![Riftlend flow](https://github.com/user-attachments/assets/83b0251a-6685-46be-b11f-952e3aa74d64)

Each LendingPool instance is:

- Controlled by its designated `LendingPoolAddressesProvider`
- Configured through the `LendingPoolConfigurator`
- Capable of cross-chain operations through the OP Stack

## How it Works

### Core Concepts

RiftLend's architecture is built on Aave V2's battle-tested foundation, with key modifications to enable cross-chain functionality. Here are the fundamental concepts:

1. **Markets and Lending Pools**

   - Each supported asset (e.g., USDC, UNI) has its own dedicated LendingPool
   - LendingPools manage all lending and borrowing activities for their respective assets across the supported L2 chains

2. **Proxy Architecture**

   - Each LendingPool operates behind an upgradeable proxy
   - Users interact with the proxy, which forwards calls to the implementation
   - Enables protocol upgrades while preserving state and balances

3. **Address Management**

   - The `LendingPoolAddressesProvider` serves as:
     - Central registry for protocol addresses
     - Factory for proxy contracts
     - Administrator for implementation updates
     - Manager of protocol permissions

4. **Protocol Governance**
   - Maintains ownership of `LendingPoolAddressesProvider`
   - Controls protocol upgrades and risk parameters
   - Manages cross-chain configurations

### User Interactions

![ActionX flow Riftlend](https://github.com/user-attachments/assets/9d0f567d-8037-411c-a8bb-fb053001aaa9)

RiftLend supports various state-changing actions (referred to as `ActionX`) including lending, borrowing, withdrawing, and repaying loans. Here's a detailed breakdown of how these cross-chain actions are processed:

**1. Action Initiation**

- User interacts with RiftLend's interface to initiate an action (e.g., lending USDC)
- The protocol receives the request and validates user inputs

**2. Chain Determination**

- Protocol checks if the action needs to be executed:
  - On the current chain (local execution)
  - On a different chain within the OP Stack (cross-chain execution)

**3. Local Execution Path**

- For same-chain actions:
  - Action is executed directly on the current chain
  - State changes are applied immediately
  - An `ActionExecuted` event is emitted with transaction details

**4. Cross-Chain Execution Path**

- For cross-chain actions:

  1. Protocol emits a `CrossChainAction` event containing:
     - Action type (lend, borrow, etc.)
     - Target chain identifier
     - Required parameters
     - User address
  2. Indexer monitors and captures the event
  3. Relayer constructs a formatted cross-chain message with:
     - Action specifications
     - Validated parameters
     - Required signatures
  4. Message is dispatched to target chain via OP Stack's messaging system
  5. Target chain:
     - Receives and validates the message
     - Executes action through LendingPool's `dispatch()` method
     - Updates state and emits confirmation events

The protocol maintains consistency by using standardized message formats and validation across all supported chains, ensuring reliable cross-chain operations.

## Token Architecture: aTokens, SuperChainAssets, and Underlying Assets

In Aave V2, when users supply assets like USDC to the protocol, these supplied assets are called "underlying assets". In return for supplying these assets, users receive "aTokens" which represent their deposit. aTokens follow a simple naming convention - the letter "a" followed by the asset name (e.g. aUSDC for USDC deposits, aSTK for STK deposits).

RiftLend introduces a new paradigm across the superchain called "SuperChainAssets". These are wrapper tokens that provide a seamless cross-chain experience for users. When users deposit an underlying asset like USDC, they first receive a SuperChainAsset (e.g. superUSDC). This SuperChainAsset then acts as the underlying asset for minting aTokens.

The relationship between these tokens is:

1. User deposits underlying asset (e.g. USDC)
2. Protocol mints SuperChainAsset (e.g. superUSDC)
3. SuperChainAsset is used to mint aTokens (e.g. aUSDC)

This architecture enables efficient cross-chain operations while maintaining compatibility with Aave's battle-tested token model.

This can be visualized in following fashion

![aTokens](https://github.com/user-attachments/assets/f931a3c5-656e-4d94-8ac3-93a4933e1059)

## Withdraw & Bridge

RiftLend introduces an innovative approach to cross-chain liquidity management that differs from traditional bridge patterns. While initially bootstrapped like typical DeFi protocols, once RiftLend achieves significant liquidity across chains, it eliminates the need for constant "burn and mint" operations between chains.

The key innovation is the `SuperchainAsset` - a wrapper token that enables seamless cross-chain transfers without always moving the underlying asset. For example, when bridging USDC between chains, instead of transferring the actual USDC, RiftLend moves the `superUSDC` wrapper token while keeping the underlying USDC on the source chain.

To illustrate with an example:

1. Lender1 deposits `100 USDC` to the Lending Pool on Chain A and receives `100 superUSDC`
2. Lender1 wants to withdraw their `100 USDC` on Chain B
3. RiftLend handles this in one of two ways:

**Scenario 1: Sufficient Liquidity on Destination Chain**

- If Chain B has enough USDC liquidity, Lender1 can instantly withdraw by converting their `superUSDC` to USDC directly on Chain B
- No actual USDC needs to be bridged from Chain A to B
- This enables near-instant withdrawals with minimal gas costs

**Scenario 2: Insufficient Liquidity on Destination Chain**

- If Chain B lacks sufficient USDC liquidity, the underlying USDC must be bridged from Chain A to B
- RiftLend initiates a bridge transfer of the actual USDC tokens
- Once bridged, Lender1 can complete their withdrawal on Chain B

This dual approach optimizes for both speed and capital efficiency while maintaining full asset backing across the system.

## 🤝 Contributing

We welcome contributions to RiftLend! Here's how you can get involved:

1. Check our [Projects board](https://github.com/RiftLend/monorepo-v1/projects?query=is%3Aopen) to see what we're working on
2. For major changes, please open an issue first to discuss your proposed changes
3. Join our [Discord community](https://discord.gg/B4HxhA55d2) to connect with other contributors
4. Follow our contribution guidelines:
   - Fork the repository
   - Create a new branch for your feature
   - Write clear commit messages
   - Add tests for new functionality
   - Submit a pull request
