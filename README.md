# AON (All-Or-Nothing) Crowdfunding Smart Contracts

A decentralized crowdfunding platform implementing an "All-Or-Nothing" funding model with cross-chain support. Contributors can pledge funds to campaigns, and creators can only claim funds if the funding goal is reached within the specified timeframe.

## Features

- ✅ **All-Or-Nothing Funding Model**: Funds are only released when goals are met
- 🔒 **Non-Upgradeable Proxy Pattern**: Secure, gas-efficient campaign deployment
- 🌉 **Cross-Chain Support**: EIP-712 signatures for cross-chain operations
- 🏭 **Factory Pattern**: Streamlined campaign creation and management
- 📊 **Pluggable Goal Strategies**: Flexible funding criteria (native tokens, oracles, etc.)
- 🔧 **CLI Tools**: Complete command-line interface for easy interaction
- 🐳 **Docker Support**: Local development environment with Anvil

## Quick Start

### Using the CLI (Recommended)

See [cli/README.md](cli/README.md) for more details.

## Architecture

The AON system implements a sophisticated crowdfunding architecture with several key components:

- **Aon.sol**: Core campaign logic with state management and contribution handling
- **Factory.sol**: Campaign deployment and management
- **AonProxy.sol**: Gas-efficient proxy pattern for campaign instances
- **AonGoalReachedNative.sol**: Pluggable strategy for goal validation

For detailed architectural documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Integration

### For Platforms

The AON contracts are designed for easy integration into existing platforms:

```typescript
// Example: Create a campaign programmatically
const factory = new ethers.Contract(factoryAddress, factoryAbi, signer);
const tx = await factory.create(
  creatorAddress,
  goalInWei,
  durationInSeconds,
  goalStrategyAddress,
  claimOrRefundWindow
);
```

## Network Support

- **Local Development**: Anvil (Chain ID: 31337)
- **RSK Testnet**: Chain ID 31
- **RSK Mainnet**: Chain ID 30

The contracts are designed to work on any EVM-compatible network with minimal configuration changes.

## Security

- ✅ Non-upgradeable proxies prevent admin rug pulls
- ✅ Re-entrancy protection on all fund operations  
- ✅ EIP-712 signatures for cross-chain operations
- ✅ Comprehensive test coverage
- ✅ Time-locked claim and refund windows

For security considerations and audit information, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and add tests
4. Run the test suite: `forge test`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.