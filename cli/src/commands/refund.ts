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

export const refundCommand = new Command('refund')
  .description('Refund your contribution from an AON campaign')
  .argument('<campaign>', 'Campaign contract address')
  .option('-p, --processing-fee <amount>', 'Processing fee in RBTC (optional)', '0')
  .option('-n, --network <network>', 'Network to use', 'local')
  .option('-k, --private-key <key>', 'Private key (or use PRIVATE_KEY env var)')
  .option('-y, --yes', 'Skip confirmation prompts')
  .action(async (campaign, options) => {
    try {
      // Validate inputs
      if (!isValidEthereumAddress(campaign)) {
        logError('Invalid campaign address');
        process.exit(1);
      }

      const processingFee = validateEthAmount(options.processingFee, true); // Allow zero for processing fees

      const privateKey = options.privateKey || getPrivateKeyFromEnv();
      if (!privateKey) {
        logError('Private key required for refund');
        process.exit(1);
      }

      const manager = new ContractManager(options.network, privateKey);
      const contributor = manager.signer?.address;

      if (!contributor) {
        logError('Unable to determine contributor address');
        process.exit(1);
      }

      // Get contribution and campaign info
      const spinner = createSpinner('Checking refund eligibility...').start();
      
      try {
        const [campaignInfo, contributionInfo] = await Promise.all([
          manager.getCampaignInfo(campaign),
          manager.getContributionInfo(campaign, contributor, processingFee),
        ]);

        spinner.stop();

        // Display refund details
        console.log(chalk.blue('Refund Details:'));
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
        console.log(`Creator: ${chalk.green(formatAddress(campaignInfo.creator))}`);
        console.log(`Your Contribution: ${chalk.green(contributionInfo.amount)} RBTC`);
        console.log(`Processing Fee: ${chalk.gray(processingFee)} RBTC`);
        console.log(`Refund Amount: ${chalk.yellow(contributionInfo.refundAmount)} RBTC`);
        console.log(`Campaign Status: ${campaignInfo.status === 0 ? chalk.blue('Active') : 
                                        campaignInfo.status === 1 ? chalk.yellow('Cancelled') : 
                                        chalk.green('Claimed')}`);

        // Check eligibility
        if (!contributionInfo.canRefund) {
          logError('Refund not available for this contribution');
          
          if (parseFloat(contributionInfo.amount) === 0) {
            logInfo('No contribution found for this address');
          } else if (campaignInfo.status === 2) {
            logInfo('Campaign funds have been claimed by creator');
          } else if (campaignInfo.goalReached && campaignInfo.status === 0) {
            logInfo('Campaign goal reached and still active - cannot refund');
          }
          
          process.exit(1);
        }

        if (parseFloat(contributionInfo.refundAmount) === 0) {
          logError('No refund amount available');
          process.exit(1);
        }

        if (!options.yes) {
          const shouldRefund = await confirmAction('\nProceed with refund?');
          if (!shouldRefund) {
            logInfo('Refund cancelled');
            return;
          }
        }

        const refundSpinner = createSpinner('Processing refund...').start();

        try {
          const txHash = await manager.refund(campaign, processingFee);
          refundSpinner.stop();

          logSuccess('Refund processed successfully!');
          console.log(`Transaction: ${chalk.blue(txHash)}`);
          console.log(`Refunded: ${chalk.green(contributionInfo.refundAmount)} RBTC`);

        } catch (refundError) {
          refundSpinner.stop();
          
          if (refundError instanceof Error) {
            if (refundError.message.includes('execution reverted')) {
              logError('Refund rejected by contract');
              logInfo('Campaign state may have changed since last check');
            } else if (refundError.message.includes('insufficient funds')) {
              logError('Contract has insufficient funds for refund');
            } else {
              logError(`Refund failed: ${refundError.message}`);
            }
          } else {
            logError(`Refund failed: ${refundError}`);
          }
          
          process.exit(1);
        }

      } catch (infoError) {
        spinner.stop();
        logError(`Failed to check refund eligibility: ${infoError}`);
        process.exit(1);
      }

    } catch (error) {
      logError(`Refund error: ${error}`);
      process.exit(1);
    }
  });
