# AON CLI Command Development Rules

## Command Structure Template

### Basic Command Structure
```typescript
import { Command } from 'commander';
import chalk from 'chalk';
import { ContractManager } from '../lib/contract';
import { 
  logSuccess, 
  logError, 
  logInfo, 
  createSpinner, 
  getPrivateKeyFromEnv,
  validateEthAmount,
  isValidEthereumAddress,
  confirmAction,
  formatAddress 
} from '../lib/utils';

export const commandName = new Command('command-name')
  .description('Command description')
  .argument('<required>', 'Argument description')
  .option('-o, --option <value>', 'Option description', 'default')
  .option('-n, --network <network>', 'Network to use', 'local')
  .option('-k, --private-key <key>', 'Private key (or use PRIVATE_KEY env var)')
  .option('-y, --yes', 'Skip confirmation prompts')
  .action(async (args, options) => {
    try {
      // Validation
      if (!isValidEthereumAddress(args)) {
        logError('Invalid address');
        process.exit(1);
      }

      const amount = validateEthAmount(options.amount);
      const privateKey = options.privateKey || getPrivateKeyFromEnv();
      
      if (!privateKey) {
        logError('Private key required');
        process.exit(1);
      }

      // Setup
      const manager = new ContractManager(options.network, privateKey);
      
      // Display info
      console.log(chalk.blue('Operation Details:'));
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Address: ${chalk.green(formatAddress(args))}`);
      console.log(`Amount: ${chalk.yellow(amount)} RBTC`);

      // Confirmation
      if (!options.yes) {
        const shouldProceed = await confirmAction('\nProceed?');
        if (!shouldProceed) {
          logInfo('Operation cancelled');
          return;
        }
      }

      // Execute
      const spinner = createSpinner('Processing...').start();
      try {
        const txHash = await manager.methodName(args, amount);
        spinner.stop();
        
        logSuccess('Operation completed successfully!');
        console.log(`Transaction: ${chalk.blue(txHash)}`);
        
      } catch (operationError) {
        spinner.stop();
        // Handle specific errors
        if (operationError instanceof Error) {
          if (operationError.message.includes('specific error')) {
            logError('Specific error message');
            logInfo('Helpful suggestion');
          } else {
            logError(`Operation failed: ${operationError.message}`);
          }
        } else {
          logError(`Operation failed: ${operationError}`);
        }
        process.exit(1);
      }

    } catch (error) {
      logError(`Command error: ${error}`);
      process.exit(1);
    }
  });
```

## Command Categories

### Campaign Management Commands
- **campaign create** - Create new campaigns
- **campaign info** - Display campaign information
- **campaign list** - List campaigns (if implemented)

### Contribution Commands  
- **contribute** - Make contributions with fees
- **contribute info** - Check contribution status

### Campaign Action Commands
- **claim** - Claim funds (creator only)
- **refund** - Request refunds with processing fees
- **cancel** - Cancel campaigns

## Parameter Patterns

### Amount Parameters
```typescript
.requiredOption('-a, --amount <amount>', 'Amount in RBTC')
.option('-c, --creator-fee <amount>', 'Creator fee in RBTC', '0')
.option('-f, --contributor-fee <amount>', 'Contributor fee in RBTC', '0')
.option('-p, --processing-fee <amount>', 'Processing fee in RBTC', '0')
```

### Address Parameters
```typescript
.argument('<campaign>', 'Campaign contract address')
.argument('<contributor>', 'Contributor address')
.requiredOption('-c, --creator <address>', 'Creator address')
```

### Common Options
```typescript
.option('-n, --network <network>', 'Network to use', 'local')
.option('-k, --private-key <key>', 'Private key (or use PRIVATE_KEY env var)')
.option('-y, --yes', 'Skip confirmation prompts')
```

## Display Patterns

### Campaign Information Display
```typescript
console.log(chalk.blue('Campaign Information:'));
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`Campaign: ${chalk.green(formatAddress(info.address))}`);
console.log(`Creator: ${chalk.green(formatAddress(info.creator))}`);
console.log(`Goal: ${chalk.green(info.goal)} RBTC`);
console.log(`Raised: ${chalk.green(info.balance)} RBTC`);
console.log(`Progress: ${chalk.yellow(((parseFloat(info.balance) / parseFloat(info.goal)) * 100).toFixed(2))}%`);
console.log(`Status: ${formatCampaignStatus(info.status)}`);
console.log(`End Time: ${chalk.gray(formatTime(info.endTime))}`);
console.log(`Time Remaining: ${formatTimeRemaining(info.endTime)}`);
console.log(`Creator Fees: ${chalk.gray(info.totalCreatorFee)} RBTC`);
if (parseFloat(info.totalContributorFee) > 0) {
  console.log(`Contributor Fees: ${chalk.cyan(info.totalContributorFee)} RBTC`);
}
```

### Transaction Success Display
```typescript
logSuccess('Operation completed successfully!');
console.log(`Transaction: ${chalk.blue(txHash)}`);
console.log(`Amount: ${chalk.green(amount)} RBTC`);
console.log(`Creator Fee: ${chalk.gray(creatorFee)} RBTC`);
if (parseFloat(contributorFee) > 0) {
  console.log(`Contributor Fee: ${chalk.cyan(contributorFee)} RBTC`);
}
```

## Error Handling Patterns

### Contract Error Handling
```typescript
} catch (operationError) {
  spinner.stop();
  
  if (operationError instanceof Error) {
    if (operationError.message.includes('insufficient funds')) {
      logError('Insufficient funds for operation');
      logInfo('Ensure your account has enough RBTC for the amount plus gas fees');
    } else if (operationError.message.includes('execution reverted')) {
      logError('Operation rejected by contract');
      logInfo('Check campaign status and parameters');
    } else if (operationError.message.includes('ContributorFeeCannotExceedContributionAmount')) {
      logError('Contributor fee cannot exceed or equal contribution amount');
      logInfo('Contributor fee must be less than the contribution amount');
    } else if (operationError.message.includes('ProcessingFeeHigherThanRefundAmount')) {
      logError('Processing fee cannot exceed refund amount');
      logInfo('Processing fee must be less than the refund amount');
    } else {
      logError(`Operation failed: ${operationError.message}`);
    }
  } else {
    logError(`Operation failed: ${operationError}`);
  }
  
  process.exit(1);
}
```

### Validation Error Handling
```typescript
// Address validation
if (!isValidEthereumAddress(campaign)) {
  logError('Invalid campaign address');
  process.exit(1);
}

// Amount validation
const amount = validateEthAmount(options.amount);
const creatorFee = validateEthAmount(options.creatorFee, true); // Allow zero
const contributorFee = validateEthAmount(options.contributorFee, true); // Allow zero

// Private key validation
const privateKey = options.privateKey || getPrivateKeyFromEnv();
if (!privateKey) {
  logError('Private key required for operation');
  process.exit(1);
}
```

## Spinner Usage

### Standard Pattern
```typescript
const spinner = createSpinner('Operation description...').start();

try {
  const result = await manager.operationMethod();
  spinner.stop();
  
  logSuccess('Operation completed!');
  // Display results
  
} catch (error) {
  spinner.stop();
  // Handle error
}
```

### Multiple Operations
```typescript
const infoSpinner = createSpinner('Fetching information...').start();
const [campaignInfo, contributionInfo] = await Promise.all([
  manager.getCampaignInfo(campaign),
  manager.getContributionInfo(campaign, contributor, processingFee),
]);
infoSpinner.stop();

const operationSpinner = createSpinner('Processing operation...').start();
const txHash = await manager.operationMethod();
operationSpinner.stop();
```

## Confirmation Patterns

### Standard Confirmation
```typescript
if (!options.yes) {
  const shouldProceed = await confirmAction('\nProceed with operation?');
  if (!shouldProceed) {
    logInfo('Operation cancelled');
    return;
  }
}
```

### Detailed Confirmation
```typescript
if (!options.yes) {
  console.log('\nOperation Summary:');
  console.log(`Amount: ${chalk.yellow(amount)} RBTC`);
  console.log(`Creator Fee: ${chalk.gray(creatorFee)} RBTC`);
  console.log(`Total: ${chalk.yellow((parseFloat(amount) + parseFloat(creatorFee)).toFixed(18))} RBTC`);
  
  const shouldProceed = await confirmAction('\nProceed with operation?');
  if (!shouldProceed) {
    logInfo('Operation cancelled');
    return;
  }
}
```

## Subcommand Patterns

### Nested Commands
```typescript
export const mainCommand = new Command('main')
  .description('Main command description')
  .addCommand(
    new Command('subcommand')
      .description('Subcommand description')
      .argument('<arg>', 'Argument description')
      .option('-o, --option <value>', 'Option description')
      .action(async (arg, options) => {
        // Subcommand implementation
      })
  );
```

## Help Text Guidelines

### Command Descriptions
- Use clear, concise descriptions
- Mention key functionality
- Include parameter requirements

### Option Descriptions
- Explain what the option does
- Include units (RBTC, seconds, etc.)
- Mention default values
- Note if optional

### Argument Descriptions
- Explain what the argument represents
- Include format requirements
- Mention validation rules

## Testing Guidelines

### Before Committing
1. Run `npm run build` to check compilation
2. Test with local network
3. Verify error handling
4. Check help text completeness
5. Test with various parameter combinations

### Common Test Cases
- Valid inputs with all options
- Invalid addresses
- Invalid amounts
- Missing required parameters
- Network errors
- Contract errors

## Remember
- Always validate user inputs
- Provide clear error messages
- Use consistent parameter naming
- Handle both success and error cases
- Include comprehensive help text
- Test all error scenarios
- Use spinners for async operations
- Follow existing patterns for consistency
