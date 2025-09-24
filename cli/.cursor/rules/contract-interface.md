# AON Contract Interface Rules

## Contract ABI Management

### ABI Definition Location
The contract ABI is defined in `src/lib/contract.ts` in the `AON_ABI` constant using `parseAbi()`.

### Current Contract Interface

#### Core Functions
```typescript
// Campaign info
'function creator() external view returns (address)'
'function goal() external view returns (uint256)'
'function endTime() external view returns (uint256)'
'function status() external view returns (uint8)'
'function totalCreatorFee() external view returns (uint256)'
'function totalContributorFee() external view returns (uint256)'
'function claimOrRefundWindow() external view returns (uint256)'
'function contributions(address) external view returns (uint256)'

// Actions
'function contribute(uint256 creatorFee, uint256 contributorFee) external payable'
'function contributeFor(address contributor, uint256 creatorFee, uint256 contributorFee) external payable'
'function refund(uint256 processingFee) external'
'function claim() external'
'function cancel() external'

// Validation
'function canRefund(address contributor, uint256 processingFee) external view returns (uint256, uint256)'
'function canClaim(address) external view returns (uint256, uint256)'
'function canContribute(uint256) external view returns (bool)'
'function canCancel() external view returns (bool)'
'function isSuccessful() external view returns (bool)'
'function isFailed() external view returns (bool)'
'function isUnclaimed() external view returns (bool)'
```

#### Events
```typescript
'event ContributionReceived(address indexed contributor, uint256 amount)'
'event ContributionRefunded(address indexed contributor, uint256 amount)'
'event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount)'
'event Cancelled()'
```

#### Errors
```typescript
'error GoalNotReached()'
'error GoalReachedAlready()'
'error InvalidContribution()'
'error AlreadyClaimed()'
'error OnlyCreatorCanClaim()'
'error CannotClaimCancelledContract()'
'error CannotClaimClaimedContract()'
'error CannotClaimFailedContract()'
'error CannotClaimUnclaimedContract()'
'error CannotRefundZeroContribution()'
'error CannotRefundClaimedContract()'
'error InsufficientBalanceForRefund(uint256 balance, uint256 refundAmount, uint256 goal)'
'error ContributorFeeCannotExceedContributionAmount()'
'error ProcessingFeeHigherThanRefundAmount(uint256 refundAmount, uint256 processingFee)'
```

## ContractManager Methods

### Core Methods
```typescript
// Campaign management
async getCampaignInfo(campaignAddress: string): Promise<CampaignInfo>
async createCampaign(creator: string, goalInEther: string, durationInSeconds: number, claimOrRefundWindow: number): Promise<string>

// Contributions
async contribute(campaignAddress: string, amountInEther: string, creatorFeeInEther: string = '0', contributorFeeInEther: string = '0'): Promise<Hash>
async getContributionInfo(campaignAddress: string, contributor: string, processingFeeInEther: string = '0'): Promise<ContributionInfo>

// Campaign actions
async refund(campaignAddress: string, processingFeeInEther: string = '0'): Promise<Hash>
async claim(campaignAddress: string): Promise<Hash>
async cancel(campaignAddress: string): Promise<Hash>

// Validation
async canClaim(campaignAddress: string, claimer: string): Promise<{ canClaim: boolean; creatorAmount: string; nonce: string; error?: string }>
```

## Type Definitions

### CampaignInfo Interface
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

### ContributionInfo Interface
```typescript
interface ContributionInfo {
  contributor: string;
  amount: string;
  canRefund: boolean;
  refundAmount: string;
}
```

## Parameter Naming Conventions

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

## Error Handling Patterns

### Contract Error Mapping
```typescript
// In canClaim method
switch (errorName) {
  case 'OnlyCreatorCanClaim':
    errorMessage = 'Only the campaign creator can claim funds';
    break;
  case 'CannotClaimCancelledContract':
    errorMessage = 'Cannot claim from cancelled campaign';
    break;
  case 'AlreadyClaimed':
    errorMessage = 'Funds have already been claimed';
    break;
  // ... more cases
}
```

### Command Error Handling
```typescript
} catch (contributionError) {
  if (contributionError.message.includes('ContributorFeeCannotExceedContributionAmount')) {
    logError('Contributor fee cannot exceed or equal contribution amount');
    logInfo('Contributor fee must be less than the contribution amount');
  }
  // ... more error cases
}
```

## When Contract Changes

### Required Updates
1. **Update ABI** in `contract.ts` - Add/remove/modify function signatures
2. **Update Method Signatures** - Change parameter names and return types
3. **Update Type Definitions** - Modify interfaces in `types/index.ts`
4. **Update Commands** - Change command options and parameter handling
5. **Update Error Handling** - Add new error cases and messages
6. **Test All Commands** - Ensure all functionality works with new interface

### Common Changes
- Function parameter renames (fee → creatorFee, tip → contributorFee)
- Return value changes (totalFee → totalCreatorFee + totalContributorFee)
- New required parameters (processingFee in refund)
- Error name changes (TipCannotExceedContributionAmount → ContributorFeeCannotExceedContributionAmount)

## Validation Rules

### Amount Validation
```typescript
const amount = validateEthAmount(options.amount);
const creatorFee = validateEthAmount(options.creatorFee, true); // Allow zero
const contributorFee = validateEthAmount(options.contributorFee, true); // Allow zero
```

### Address Validation
```typescript
if (!isValidEthereumAddress(campaign)) {
  logError('Invalid campaign address');
  process.exit(1);
}
```

### Private Key Handling
```typescript
const privateKey = options.privateKey || getPrivateKeyFromEnv();
if (!privateKey) {
  logError('Private key required for operation');
  process.exit(1);
}
```

## Remember
- Always update ABI when contract interface changes
- Maintain consistent parameter naming across commands
- Handle all possible contract errors with user-friendly messages
- Test all commands after contract updates
- Keep type definitions in sync with contract interface
