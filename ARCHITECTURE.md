# AON (All-Or-Nothing) Crowdfunding Smart Contract Architecture

## Overview

The AON system is a crowdfunding smart contract that implements an "All-Or-Nothing" funding model. Contributors can pledge funds to campaigns, and creators can only claim the funds if the funding goal is reached within the specified timeframe. If the goal is not met, contributors can refund their contributions.

## Core Architectural Principles

### 1. **Non-Upgradeable Proxy Pattern**

OpenZeppelin's proxy pattern is used to separate the campaign business logic (implementation) from its state (proxy). This allows for a more gas efficient deployment of campaigns. Each new campaign is deployed as a proxy contract pointing to a shared implementation contract.

For security reasons, and due to the short-lived nature of the majority of crowdfunding campaigns, the proxies are non-upgradeable, meaning that the implementation contract used by the proxy is immutable.

### 2. **Factory Pattern for Campaign Creation**

The factory contract is used to deploy new campaigns. It is responsible for creating new proxy contracts and initializing them with the correct parameters. The factory contract is also responsible for upgrading the implementation contract used by the proxy.

Anyone can call the campaign creation, but implementation upgrades are only allowed by the factory owner.

### 3. **Strategy Pattern for Goal Validation**

The goal validation strategy is a pluggable strategy that allows different funding criteria. Currently, it implements native token balance checking.

The strategy is pluggable, meaning that it can be replaced with a different strategy if needed. This allows for future extensibility and flexibility, such as token-based funding or oracle-based funding (eg: for USD-based goals).

### 4. **State Machine Design**
- Clear campaign states: Active, Cancelled, Claimed
- Deterministic state transitions with comprehensive validation
- Derived states (Failed, Successful, Unclaimed, Finalized) for business logic

### 5. **EIP-712 Integration for Cross-Chain Operations**
- Typed structured data signing for secure off-chain authorizations
- Enables integration with swap contracts for cross-chain functionality
- Replay protection through nonce management

The EIP-712 integration is used to enable cross-chain refunds and claiming, eg: swapped refunds/claiming to main-chain or Lightning Bitcoin.

## System Components

### Core Contracts

#### 1. **Aon.sol** - Implementation Contract (Business Logic)
The heart of the system, implementing the crowdfunding campaign logic.

**Key Responsibilities:**
- **Contribution Management**: Accept and track contributor funds
- **State Management**: Maintain campaign lifecycle and enforce business rules
- **Refund Logic**: Handle contributor refunds under various conditions
- **Claim Logic**: Enable creator fund withdrawal when goals are met
- **Cross-Chain Integration**: Support for swap contract interactions via EIP-712 signatures

**State Management:**
```solidity
enum Status {
    Active,    // Campaign accepting contributions
    Cancelled, // Campaign terminated by creator/admin
    Claimed    // Funds successfully claimed by creator
}
```

**Derived States:**
- `isFailed()`: Time expired without reaching goal
- `isSuccessful()`: Goal reached and claimable
- `isUnclaimed()`: Goal reached but claim window expired
- `isFinalized()`: All operations complete, contract can be cleaned up

**Security Features:**
- Re-entrancy protection through state updates before external calls
- EIP-712 signature validation for cross-chain operations
- Nonce-based replay protection

#### 2. **AonProxy.sol** - Proxy Contract (State)
Custom proxy contract that routes calls to the implementation while maintaining isolated state.

**Key Features:**
- **Immutable Implementation**: Gas-efficient storage of implementation address
- **Direct Transfer Protection**: Prevents accidental ETH transfers that bypass campaign logic
- **Transparent Proxy**: All calls forwarded to implementation except for proxy-specific functions

**Security Considerations:**
- Blocks direct ETH transfers to prevent bypassing contribution tracking
- Immutable implementation address prevents proxy hijacking
- Minimal attack surface with simple forwarding logic

#### 3. **Factory.sol** - Campaign Deployment
Manages the creation and configuration of new campaigns.

**Key Responsibilities:**
- Deploy minimal proxies for gas efficiency
- Provide administrative controls (implementation upgrades)

**Design Benefits:**
- **Gas Efficiency**: Minimal proxy pattern reduces deployment costs
- **Consistency**: Ensures all campaigns follow the same initialization process
- **Upgradeability**: Can deploy new implementation versions
- **Governance**: Centralized control for system-wide changes

#### 4. **AonGoalReachedNative.sol** - Goal Validation Strategy
Implements the strategy pattern for determining when funding goals are reached.

**Current Implementation:**
- Compares contract balance to target goal
- Called by the Aon contract to determine funding status
- Stateless design for simplicity and gas efficiency

**Extensibility:**
- Interface allows for alternative implementations
- Could support token-based funding, oracle integration, or complex criteria
- Strategy can be specified per campaign for flexibility

### Other Architectural Patterns and Design Decisions

#### 1. **Timelock and Window Management**
**Decision**: Sequenced and separate claim and refund windows, ie: claim window must expire before refund window starts.
**Rationale**:
- Provides time for creators to claim funds
- Allows contributor refunds if creators don't claim
- Enables platform fund recovery for abandoned campaigns

#### 2. **Dynamic Fee Model**
**Decision**: The fee is passed as a parameter to individual contribution calls, and is deducted from the claiming amount automatically. The contract owner is the recipient of the fee.
**Rationale**:
- Provides a source of revenue for the owner and maintainer of the contract
- Allows flexible fee models, eg: variable platform fee

#### 3. **Granular Custom Errors**
**Decision**: Use custom errors for each state transition and validation.
**Rationale**:
- Provides more detailed error messages
- Allows for more granular error handling
- Provides more detailed logging

#### 4. **Public Validation Methods**
**Decision**: Public view functions to check operation validity before execution.
**Rationale**:
- Minimize invalid transaction executions to avoid gas waste.
- Pro-actively inform users of invalid operations before they are executed.

## Security Architecture

### Access Control
- **Creator Rights**: Claim funds, cancel campaigns
- **Factory Owner Rights**: Cancel campaigns, swipe abandoned funds, upgrade implementations
- **Contributor Rights**: Refund contributions under specific conditions
- **Public Rights**: View campaign state, contribute, create campaign

### Fund Safety Mechanisms
1. **Goal-Based Claiming**: Funds only claimable when goals are met
2. **Time-Based Windows**: Structured timeframes for claims and refunds
3. **Platform Fee Protection**: Automatic platform fee deduction and transfer (on claiming only)
4. **Abandoned Fund Recovery**: Factory owner can recover funds after extended periods

### Signature Security
- **EIP-712 Domain Separation**: Prevents cross-contract replay attacks
- **Nonce Management**: Prevents signature replay within contracts
- **Deadline Enforcement**: Time-bounded signature validity
- **Signer Verification**: Cryptographic proof of authorization

## Integration Points

### Cross-Chain Functionality
The system supports cross-chain operations through swap contracts:

1. **Signed Refunds**: Contributors can authorize refunds to swap contracts
2. **Signed Claims**: Creators can authorize fund claims to swap contracts
3. **Hash Time Locked Contracts (HTLCs)**: Integration with atomic swap mechanisms

### Platform Integration
- **Event Emission**: Comprehensive events for off-chain indexing
- **Query Functions**: Read-only functions for UI integration
- **Validation Functions**: Public functions to check operation validity before execution

## Deployment Architecture

### Deployment Sequence
1. **Implementation Deployment**: Deploy Aon logic contract
2. **Strategy Deployment**: Deploy goal-reached strategy contract
3. **Factory Deployment**: Deploy factory with implementation reference
4. **Campaign Creation**: Factory creates proxy instances as needed

### Configuration Management
- Implementation contracts are immutable once deployed
- Factory owner can upgrade implementation for new campaigns
- Individual campaigns maintain their configuration throughout their lifecycle

## Operational Considerations

### Monitoring and Maintenance
- **Event Logging**: Comprehensive event emission for off-chain tracking
- **State Queries**: Public view functions for system monitoring
- **Emergency Controls**: Factory owner controls for edge case management

### Scalability
- **Stateless Strategies**: Goal validation strategies don't maintain state
- **Independent Campaigns**: Each campaign operates independently
- **Parallel Processing**: Multiple campaigns can be created and operated simultaneously

## Future Extensibility

The architecture supports several extension points:

1. **Alternative Goal Strategies**: Token-based funding, oracle integration, milestone-based goals
2. **Enhanced Cross-Chain Support**: Additional swap contract integrations
3. **Governance Integration**: DAO-based factory ownership and decision making
4. **Advanced Fee Models**: Dynamic fees, creator fee sharing, token-based incentives

## Risk Considerations

### Smart Contract Risks
- **Implementation Bugs**: Affect all campaigns using the same implementation
- **Proxy Risks**: Minimal risk due to simple proxy design
- **Strategy Risks**: Malicious or buggy goal strategies could affect individual campaigns

### Economic Risks
- **Creator Abandonment**: Mitigated by fund swiping mechanism
- **Platform Fee Attacks**: Protected by automatic fee deduction
- **Cross-Chain Failures**: Risk in swap contract interactions, failed swap operations are **not** handled by the contract.

### Operational Risks
- **Factory Centralization**: Factory owner has significant control
- **Upgrade Management**: Implementation upgrades affect new campaigns only
- **Key Management**: Critical for factory ownership and cross-chain operations

This architecture provides a robust, extensible foundation for all-or-nothing crowdfunding with strong security guarantees and clear operational boundaries.
