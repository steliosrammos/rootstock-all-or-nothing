# AON CLI Quick Reference

## Common Patterns

### Command Structure
```typescript
export const commandName = new Command('command-name')
  .description('Command description')
  .argument('<required>', 'Argument description')
  .option('-o, --option <value>', 'Option description', 'default')
  .action(async (args, options) => {
    // Implementation
  });
```

### Validation
```typescript
// Amount validation
const amount = validateEthAmount(options.amount);
const creatorFee = validateEthAmount(options.creatorFee, true); // Allow zero

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

### Display
```typescript
console.log(chalk.blue('Information:'));
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
console.log(`Amount: ${chalk.yellow(amount)} RBTC`);
```

### Spinner Usage
```typescript
const spinner = createSpinner('Processing...').start();
try {
  const result = await manager.method();
  spinner.stop();
  logSuccess('Completed!');
} catch (error) {
  spinner.stop();
  logError(`Failed: ${error.message}`);
}
```

### Error Handling
```typescript
} catch (error) {
  if (error.message.includes('ContributorFeeCannotExceedContributionAmount')) {
    logError('Contributor fee cannot exceed contribution amount');
    logInfo('Contributor fee must be less than the contribution amount');
  } else {
    logError(`Operation failed: ${error.message}`);
  }
  process.exit(1);
}
```

## Parameter Conventions

### Command Line Options
- `--creator-fee` or `-c` for creator fees
- `--contributor-fee` or `-f` for contributor fees  
- `--processing-fee` or `-p` for processing fees
- `--amount` or `-a` for contribution amounts

### Method Parameters
- `creatorFeeInEther` - Creator fee amount
- `contributorFeeInEther` - Contributor fee amount
- `processingFeeInEther` - Processing fee amount
- `amountInEther` - Contribution amount

## Contract Interface

### Key Methods
```typescript
// Contributions
async contribute(campaignAddress: string, amountInEther: string, creatorFeeInEther: string = '0', contributorFeeInEther: string = '0'): Promise<Hash>

// Refunds
async refund(campaignAddress: string, processingFeeInEther: string = '0'): Promise<Hash>

// Campaign info
async getCampaignInfo(campaignAddress: string): Promise<CampaignInfo>
async getContributionInfo(campaignAddress: string, contributor: string, processingFeeInEther: string = '0'): Promise<ContributionInfo>
```

### Type Definitions
```typescript
interface CampaignInfo {
  address: string;
  creator: string;
  goal: string;
  endTime: number;
  status: number;
  balance: string;
  totalCreatorFee: string;        // Changed from totalFee
  totalContributorFee: string;   // Changed from totalTip
  claimOrRefundWindow: number;
  goalReached: boolean;
  isSuccessful: boolean;
  isFailed: boolean;
  isUnclaimed: boolean;
}
```

## Common Errors

### Contract Errors
- `ContributorFeeCannotExceedContributionAmount` - Contributor fee too high
- `ProcessingFeeHigherThanRefundAmount` - Processing fee too high
- `OnlyCreatorCanClaim` - Unauthorized claim attempt

### Validation Errors
- Invalid addresses
- Invalid amounts
- Missing private keys
- Insufficient funds

## Testing Checklist

- [ ] Run `npm run build` to check compilation
- [ ] Test with valid inputs
- [ ] Test with invalid inputs
- [ ] Test error handling
- [ ] Check help text
- [ ] Test with different networks

