# AON CLI Development Rules

## Project Overview
This is a TypeScript CLI for interacting with AON (All-or-Nothing) crowdfunding contracts on Rootstock. The CLI provides commands for campaign management, contributions, refunds, and claims.

## Architecture & Structure

### Core Components
- **ContractManager** (`src/lib/contract.ts`): Main interface for blockchain interactions using viem
- **Commands** (`src/commands/`): Individual command implementations using Commander.js
- **Utils** (`src/lib/utils.ts`): Shared utilities for validation, formatting, and user interaction
- **Types** (`src/types/index.ts`): TypeScript interfaces and type definitions
- **Config** (`src/lib/config.ts`): Network and configuration management

### Key Patterns

#### Command Structure
```typescript
export const commandName = new Command('command-name')
  .description('Command description')
  .argument('<required>', 'Argument description')
  .option('-o, --option <value>', 'Option description', 'default')
  .action(async (args, options) => {
    // Implementation
  });
```

#### Error Handling
- Use `logError()`, `logSuccess()`, `logInfo()` for user feedback
- Always validate inputs with utility functions
- Use `createSpinner()` for async operations
- Handle contract errors with specific error messages

#### Contract Interactions
- All blockchain calls go through `ContractManager`
- Use `parseEther()` for amount conversions
- Always wait for transaction receipts
- Handle both success and error cases

## Fee Structure & Parameters

### Current Fee Model
- **Creator Fee**: Fee paid by the creator (deducted from claimable amount)
- **Contributor Fee**: Fee paid by the contributor (deducted from contribution amount)
- **Processing Fee**: Fee for refund processing (deducted from refund amount)

### Command Parameters
```bash
# Contribute with fees
aon-cli contribute <campaign> -a <amount> -c <creator-fee> -f <contributor-fee>

# Refund with processing fee
aon-cli refund <campaign> -p <processing-fee>
```

## Development Guidelines

### Adding New Commands
1. Create new file in `src/commands/`
2. Follow existing command structure
3. Add proper validation and error handling
4. Update main index.ts to register command
5. Add comprehensive help text

### Contract Updates
1. Update ABI definitions in `contract.ts`
2. Update method signatures and return types
3. Update related commands to use new interface
4. Update types in `types/index.ts`
5. Test all affected commands

### Validation Patterns
```typescript
// Amount validation
const amount = validateEthAmount(options.amount);

// Address validation
if (!isValidEthereumAddress(address)) {
  logError('Invalid address');
  process.exit(1);
}

// Private key handling
const privateKey = options.privateKey || getPrivateKeyFromEnv();
if (!privateKey) {
  logError('Private key required');
  process.exit(1);
}
```

### Display Patterns
```typescript
// Campaign info display
console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
console.log(`Creator: ${chalk.green(formatAddress(info.creator))}`);
console.log(`Goal: ${chalk.green(info.goal)} RBTC`);
console.log(`Raised: ${chalk.green(info.balance)} RBTC`);

// Fee display
console.log(`Creator Fees: ${chalk.gray(info.totalCreatorFee)} RBTC`);
console.log(`Contributor Fees: ${chalk.cyan(info.totalContributorFee)} RBTC`);
```

## Network Configuration

### Supported Networks
- `local` - Anvil local development
- `rsk-testnet` - Rootstock testnet
- `rsk-mainnet` - Rootstock mainnet

### Configuration
- Network configs in `src/lib/config.ts`
- Contract addresses stored per network
- RPC URLs configurable via environment

## Testing & Validation

### Before Committing
1. Run `npm run build` to check compilation
2. Test commands with local network
3. Verify error handling works correctly
4. Check help text is comprehensive

### Common Issues
- Forgot to update ABI after contract changes
- Missing error handling for new contract errors
- Inconsistent parameter naming
- Missing validation for new parameters

## File Organization

```
src/
├── commands/           # Command implementations
│   ├── campaign.ts     # Campaign management
│   ├── contribute.ts   # Contribution handling
│   ├── refund.ts       # Refund processing
│   ├── claim.ts        # Fund claiming
│   └── ...
├── lib/               # Core utilities
│   ├── contract.ts    # Blockchain interactions
│   ├── utils.ts       # Shared utilities
│   └── config.ts      # Configuration
├── types/             # Type definitions
└── index.ts          # Main entry point
```

## Key Dependencies
- `commander` - CLI framework
- `viem` - Ethereum library
- `chalk` - Terminal colors
- `table` - Table formatting

## Remember
- Always use consistent terminology (creator fee, contributor fee, processing fee)
- Maintain backward compatibility where possible
- Provide clear error messages
- Use spinners for async operations
- Validate all user inputs
- Handle both success and error cases

