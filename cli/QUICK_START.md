# AON CLI Quick Start Guide

## Installation

### Method 1: Global Installation (Recommended)
```bash
cd cli
npm install
npm run link:global
aon-cli setup init

# Optional: Set up environment variables for easier usage
cp ../env.example ../.env
aon-cli setup env  # Verify environment setup
```

### Method 2: Local Development
```bash
cd cli  
npm install
npm run build
npm run dev setup init
```

### Method 3: Automated Script
```bash
cd cli
./install.sh
```

## Essential Commands

### Environment Setup
```bash
aon-cli setup start -d          # Start Anvil node in background
aon-cli setup status            # Check status
aon-cli setup stop              # Stop local environment
aon-cli setup env               # Show environment variables and private keys
```

### Custom RPC URLs
```bash
# Use custom RPC URL (disables Anvil management)
aon-cli --rpc-url http://localhost:9545 accounts
aon-cli --rpc-url http://localhost:9545 deploy
aon-cli --rpc-url https://custom-node.com deploy --network rsk-testnet
```

### Contract Management
```bash
aon-cli deploy                  # Deploy contracts (uses .env private key)
aon-cli deploy --network rsk-testnet  # Deploy to RSK testnet
aon-cli deploy --private-key 0x...    # Override .env private key
```

### Campaign Operations
```bash
# Create campaign
aon-cli campaign create \
  --creator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --goal "10" \
  --duration "30 days"

# Get campaign info
aon-cli campaign info 0x1234...

# Cancel campaign
aon-cli campaign cancel 0x1234... --private-key 0x...
```

### Contribution Flow
```bash
# Contribute to campaign
aon-cli contribute 0x1234... \
  --amount "1" \
  --fee "0.01" \
  --private-key 0x...

# Check contribution status
aon-cli contribute info 0x1234... 0xContributorAddress...

# Refund contribution
aon-cli refund 0x1234... --private-key 0x...

# Claim funds (creator only)
aon-cli claim 0x1234... --private-key 0x...
```

### Utility Commands
```bash
aon-cli accounts                # List available accounts
aon-cli accounts --with-balances # Include balances
aon-cli balance 0xAddress...    # Check specific balance
```

## Quick Demo Flow

```bash
# 1. Setup environment
aon-cli setup start -d
aon-cli deploy

# 2. Create campaign (copy the campaign address)
aon-cli campaign create \
  --creator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --goal "1" \
  --duration "1 hour"

# 3. Contribute to campaign
aon-cli contribute CAMPAIGN_ADDRESS \
  --amount "0.5" \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# 4. Contribute more to reach goal
aon-cli contribute CAMPAIGN_ADDRESS \
  --amount "0.6" \
  --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# 5. Check campaign status
aon-cli campaign info CAMPAIGN_ADDRESS

# 6. Claim funds (creator)
aon-cli claim CAMPAIGN_ADDRESS \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## Default Anvil Accounts

| Index | Address | Private Key | Balance |
|-------|---------|-------------|---------|
| 0 | `0xf39Fd...2266` | `0xac097...2ff80` | 10,000 Ether |
| 1 | `0x70997...79C8` | `0x59c69...b690d` | 10,000 Ether |
| 2 | `0x3C44C...93BC` | `0x5de41...365a` | 10,000 Ether |

## Common Issues

**CLI not found after linking:**

npm run unlink:global && npm run link:global
```

**Changes not reflected:**
```bash
npm run build  # Always rebuild after code changes
```

**Permission errors:**
```bash
sudo chown -R $(whoami) $(npm config get prefix)/{lib/node_modules,bin,share}
```

## Development Workflow

```bash
# Make code changes
vim src/commands/deploy.ts

# Rebuild and test
npm run build
aon-cli deploy --help

# Or use npm scripts during development
npm run dev deploy --help
```

## Networks

- **local**: Anvil at `http://localhost:8545` (Chain ID: 31337)
- **rsk-testnet**: RSK Testnet (Chain ID: 31)  
- **rsk-mainnet**: RSK Mainnet (Chain ID: 30)

Use `--network` flag to specify which network to use.
