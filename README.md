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

#### Option 1: Global Installation (Easiest)

1. **Setup the CLI globally:**
   ```bash
   cd cli
   npm install
   npm run link:global          # Installs 'aon-cli' command globally
   aon-cli setup init           # Initialize configuration
   ```

2. **Start development environment:**
   ```bash
   aon-cli setup start -d       # Start local Anvil node
   aon-cli deploy               # Deploy contracts
   ```

3. **Create and manage campaigns:**
   ```bash
   # Create a campaign
   aon-cli campaign create \
     --creator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
     --goal "10" \
     --duration "30 days"
   
   # Contribute to a campaign
   aon-cli contribute CAMPAIGN_ADDRESS --amount "1"
   
   # Check campaign status
   aon-cli campaign info CAMPAIGN_ADDRESS
   ```

#### Option 2: Local Development Mode

If you prefer not to install globally:

```bash
cd cli
npm install
npm run build
npm run dev setup init        # Initialize config
npm run dev deploy            # Deploy contracts
npm run dev campaign create ...  # Run commands
```

#### Option 3: Automated Setup

Use the installation script:

```bash
cd cli
chmod +x install.sh
./install.sh                 # Interactive setup with global option
```

For complete CLI documentation, see [cli/README.md](cli/README.md).

### Using Foundry Directly

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```



deploy: 
```shell
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

add amount to deployment public key:
```shell
docker exec boltz-anvil cast send --rpc-url http://anvil:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 0x9cCA66b3F0655E8511ff25B8797034B8D99835cC --value 10ether
```

call the contribute method in the aon contract with value:
```shell
cast send 0x55652FF92Dc17a21AD6810Cce2F4703fa2339CAE "contribute(uint256)" 0 --value 879450000000000 --private-key 64b075e4ca5c8f179bcf13ba8743cebcf68c5a86051ac7afefa613332fbd19db --rpc-url http://localhost:8545
```

check if the contract contribute got the balance:
```shell
cast call 0x55652FF92Dc17a21AD6810Cce2F4703fa2339CAE "contributions(address)" 0x3e2e5183f23dbcdedfb5f48813c4208691084aec --rpc-url http://localhost:8545
```

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

### For Developers

Use the CLI to interact with contracts during development:

```bash
# Deploy to your preferred network
aon-cli deploy --network rsk-testnet

# Generate TypeScript ABIs
cd cli && npm run generate:abis
```

## Local Development

### Docker Compose Setup

Start a complete local development environment:

```bash
# Start Anvil node only
docker compose up anvil -d

# Start with block explorer (optional)
docker compose --profile with-explorer up -d

# Access block explorer at http://localhost:4000
```

### Environment Configuration

Copy the example environment file and configure for your needs:

```bash
cp env.example .env
# Edit .env with your private keys and RPC URLs
```

## Network Support

- **Local Development**: Anvil (Chain ID: 33)
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