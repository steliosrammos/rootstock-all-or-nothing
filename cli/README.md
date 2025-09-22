# AON CLI

A command-line interface for interacting with AON (All-Or-Nothing) crowdfunding smart contracts. Built with TypeScript, Viem, and Commander.js.

## Features

- 🚀 **Contract Deployment** - Deploy AON contracts to any network
- 🎯 **Campaign Management** - Create, monitor, and manage campaigns
- 💰 **Contribution Operations** - Contribute, refund, and claim funds
- 🔧 **Developer Tools** - Local Anvil setup, balance checking, account management
- 📊 **ABI Generation** - Wagmi-powered ABI generation for type safety
- 🌐 **Multi-Network Support** - Local, RSK Testnet, RSK Mainnet

## Installation

### Prerequisites

- Node.js >= 16.0.0
- Docker (for local development)
- Foundry (for contract compilation)

### Setup

#### Method 1: Local Development (Recommended)

1. **Clone and navigate to the CLI directory:**
   ```bash
   cd cli
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Build the CLI:**
   ```bash
   npm run build
   ```

4. **Link globally for direct access:**
   ```bash
   npm run link:global
   ```

5. **Initialize configuration:**
   ```bash
   aon-cli setup init
   ```

After linking, you can call `aon-cli` directly from anywhere on your system!

#### Method 2: Quick Install Script

Use the automated installation script:

```bash
chmod +x install.sh
./install.sh
```

> **Note**: If you encounter yarn-related errors, ensure you're using npm by running `npm install` instead of `yarn install`. The CLI is configured to work with npm.

## Understanding npm link

### What does `npm link` do?

`npm link` creates a global symbolic link to your CLI package, allowing you to:

1. **Call the CLI directly**: Use `aon-cli` instead of `npm run dev`
2. **Test globally**: Verify your CLI works as users would experience it
3. **Live updates**: Changes to your code are immediately available (after rebuild)
4. **Cross-directory access**: Use the CLI from any directory on your system

### npm link Workflow

```bash
# In the CLI directory
npm run link:global           # Build and link globally
aon-cli --help               # Now works from anywhere!

# Make code changes, then rebuild
npm run build                # Apply changes
aon-cli setup start          # Use updated CLI

# When done developing
npm run unlink:global        # Remove global link
```

### Alternative: Direct Binary Execution

You can also run the compiled CLI directly:

```bash
npm run build
./dist/index.js --help       # Run compiled JS directly
node dist/index.js deploy    # Alternative syntax
```

## Quick Start

### 1. Start Local Development Environment

```bash
# Using npm scripts (Method 2)
npm run dev setup start -d

# Using linked CLI (Method 1) - if you ran npm run link:global
aon-cli setup start -d

# Check status
aon-cli setup status
```

### 2. Deploy Contracts

```bash
# Deploy to local network
aon-cli deploy

# Deploy to RSK testnet
aon-cli deploy --network rsk-testnet --private-key YOUR_PRIVATE_KEY
```

### 3. Create a Campaign

```bash
aon-cli campaign create \
  --creator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --goal "10" \
  --duration "30 days" \
  --claim-window "7 days"
```

### 4. Contribute to Campaign

```bash
aon-cli contribute CAMPAIGN_ADDRESS \
  --amount "1" \
  --fee "0.01" \
  --tip "0.1"
```

## Commands Reference

### Environment Setup

```bash
# Initialize CLI configuration
aon-cli setup init

# Start local Anvil node
aon-cli setup start [-d, --detach]

# Stop local environment
aon-cli setup stop

# Check environment status
aon-cli setup status
```

### Contract Deployment

```bash
# Deploy contracts to a network
aon-cli deploy [options]

Options:
  -n, --network <network>     Network to deploy to (default: "local")
  -k, --private-key <key>     Private key for deployment
  -y, --yes                   Skip confirmation prompts
```

### Campaign Management

```bash
# Create a new campaign
aon-cli campaign create [options]

Required Options:
  -c, --creator <address>     Creator address
  -g, --goal <amount>         Funding goal in ETH
  -d, --duration <duration>   Campaign duration (e.g., "30 days")

Optional:
  -w, --claim-window <dur>    Claim/refund window (default: "7 days")
  -n, --network <network>     Network to use (default: "local")
  -k, --private-key <key>     Private key
  -y, --yes                   Skip confirmation prompts

# Get campaign information
aon-cli campaign info <address> [options]

# Cancel a campaign (creator or factory owner only)
aon-cli campaign cancel <address> [options]
```

### Contribution Operations

```bash
# Contribute to a campaign
aon-cli contribute <campaign> [options]

Required:
  -a, --amount <amount>       Amount to contribute in ETH

Optional:
  -f, --fee <amount>          Platform fee in ETH (default: "0")
  -t, --tip <amount>          Tip amount in ETH (default: "0")
  -n, --network <network>     Network to use (default: "local")
  -k, --private-key <key>     Private key
  -y, --yes                   Skip confirmation prompts

# Get contribution information
aon-cli contribute info <campaign> <contributor> [options]

# Refund your contribution
aon-cli refund <campaign> [options]

# Claim funds (creator only)
aon-cli claim <campaign> [options]
```

### Utility Commands

```bash
# List available accounts
aon-cli accounts [options]
  --with-balances             Include ETH balances (slower)
  -n, --network <network>     Network to use (default: "local")

# Check balance of an address
aon-cli balance <address> [options]
  -n, --network <network>     Network to use (default: "local")
```

### ABI Generation

```bash
# Generate TypeScript ABIs with wagmi
npm run generate:abis
```

## Configuration

The CLI uses a YAML configuration file located at `~/.aon-cli/config.yaml`. It includes:

- Network configurations (RPC URLs, chain IDs)
- Default network settings
- Deployed contract addresses

### Default Networks

- **local**: Anvil node at `http://localhost:8545` (Chain ID: 31337)
- **rsk-testnet**: RSK Testnet at `https://public-node.testnet.rsk.co` (Chain ID: 31)
- **rsk-mainnet**: RSK Mainnet at `https://public-node.rsk.co` (Chain ID: 30)

## Environment Variables

Create a `.env` file in the project root (copy from `env.example`):

```bash
# Private keys (use Anvil default for local development)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RSK_DEPLOYMENT_PRIVATE_KEY=your_rsk_private_key

# Custom RPC URLs (optional)
RSK_TESTNET_RPC_URL=https://your-custom-rpc-url
```

## Examples

### Complete Campaign Lifecycle

```bash
# 1. Start local environment
aon-cli setup start -d

# 2. Deploy contracts
aon-cli deploy

# 3. Create campaign
aon-cli campaign create \
  --creator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --goal "10" \
  --duration "30 days"

# 4. Contribute to campaign
aon-cli contribute CAMPAIGN_ADDRESS \
  --amount "5" \
  --tip "0.5" \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# 5. Check campaign status
aon-cli campaign info CAMPAIGN_ADDRESS

# 6. Claim funds (when goal is reached)
aon-cli claim CAMPAIGN_ADDRESS \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Using with RSK Networks

```bash
# Deploy to RSK testnet
aon-cli deploy \
  --network rsk-testnet \
  --private-key YOUR_PRIVATE_KEY

# Create campaign on RSK testnet
aon-cli campaign create \
  --network rsk-testnet \
  --creator YOUR_ADDRESS \
  --goal "1" \
  --duration "7 days" \
  --private-key YOUR_PRIVATE_KEY
```

## Docker Setup

The project includes a Docker Compose setup for local development:

```bash
# Start Anvil node only
docker compose up anvil -d

# Start with block explorer (optional)
docker compose --profile with-explorer up -d

# Stop all services
docker compose down
```

The block explorer (if enabled) will be available at `http://localhost:4000`.

## Troubleshooting

### Common Issues

1. **"Network connection failed"**
   - Check if Anvil is running: `aon-cli setup status`
   - Verify RPC URL in network configuration

2. **"Private key required"**
   - Set `PRIVATE_KEY` environment variable
   - Or provide via `--private-key` option

3. **"Insufficient funds"**
   - Check account balance: `aon-cli balance YOUR_ADDRESS`
   - For local development, use pre-funded Anvil accounts

4. **"Contract not deployed"**
   - Deploy contracts first: `aon-cli deploy`
   - Check deployment status in configuration
   - Make sure the network is correct (eg: 31337 for local regtest Anvil node)

5. **"Permission denied: aon-cli"**
   - This happens when the global CLI link has incorrect permissions
   - Fix by unlinking and re-linking:
     ```bash
     npm run unlink:global
     npm run link:global
     ```

### npm link Troubleshooting

**Command not found after linking:**
```bash
# Check if the link was created
npm ls -g --depth=0 | grep aon-cli

# Verify npm global bin directory is in PATH
npm config get prefix
echo $PATH

# Re-link if needed
npm run unlink:global && npm run link:global
```

**Permission errors:**
```bash
# On macOS/Linux, you might need to fix npm permissions
sudo chown -R $(whoami) $(npm config get prefix)/{lib/node_modules,bin,share}

# Or use a different global directory
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bash_profile
source ~/.bash_profile
```

**Links not updating after code changes:**
```bash
# Always rebuild after making changes
npm run build

# The link will automatically use the updated code
aon-cli --version
```

### Default Anvil Accounts

The local Anvil node comes with pre-funded accounts:

- **Account 0**: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (10,000 ETH)
  - Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

- **Account 1**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (10,000 ETH)
  - Private Key: `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`

## Development

### Building from Source

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Run in development mode
npm run dev

# Clean build artifacts
npm run clean
```

### Project Structure

```
cli/
├── src/
│   ├── commands/           # CLI command implementations
│   ├── lib/               # Core libraries (contract, config, utils)
│   ├── types/             # TypeScript type definitions
│   └── index.ts           # CLI entry point
├── wagmi.config.ts        # Wagmi configuration for ABI generation
├── package.json           # Dependencies and scripts
└── README.md             # This file
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.
