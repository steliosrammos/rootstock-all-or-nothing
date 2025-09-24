import { Command } from 'commander';
import chalk from 'chalk';
import { ContractManager } from '../lib/contract';
import { 
  logSuccess, 
  logError, 
  logInfo, 
  createSpinner, 
  getPrivateKeyFromEnv,
  isValidEthereumAddress,
  confirmAction,
  formatAddress 
} from '../lib/utils';

export const claimCommand = new Command('claim')
  .description('Claim funds from a successful AON campaign (creator only)')
  .argument('<campaign>', 'Campaign contract address')
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

      const privateKey = options.privateKey || getPrivateKeyFromEnv();
      if (!privateKey) {
        logError('Private key required for claiming');
        process.exit(1);
      }

      const manager = new ContractManager(options.network, privateKey);
      const claimer = manager.signer?.address;

      if (!claimer) {
        logError('Unable to determine claimer address');
        process.exit(1);
      }

      // Check claim eligibility using contract validation
      const spinner = createSpinner('Checking claim eligibility...').start();
      
      try {
        const [campaignInfo, claimInfo] = await Promise.all([
          manager.getCampaignInfo(campaign),
          manager.canClaim(campaign, claimer)
        ]);
        spinner.stop();

        // Display claim details
        console.log(chalk.blue('Claim Details:'));
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
        console.log(`Creator: ${chalk.green(formatAddress(campaignInfo.creator))}`);
        console.log(`Claimer: ${chalk.blue(formatAddress(claimer))}`);
        console.log(`Goal: ${chalk.green(campaignInfo.goal)} RBTC`);
        console.log(`Raised: ${chalk.green(campaignInfo.balance)} RBTC`);
        console.log(`Net Amount: ${chalk.yellow(claimInfo.creatorAmount)} RBTC`);
        console.log(`Campaign Status: ${campaignInfo.status === 0 ? chalk.blue('Active') : 
                                        campaignInfo.status === 1 ? chalk.yellow('Cancelled') : 
                                        chalk.green('Claimed')}`);

        // Check if claim is possible using contract validation
        if (!claimInfo.canClaim) {
          logError(claimInfo.error || 'Cannot claim funds');
          process.exit(1);
        }

        if (!options.yes) {
          const shouldClaim = await confirmAction('\nProceed with claim?');
          if (!shouldClaim) {
            logInfo('Claim cancelled');
            return;
          }
        }

        const claimSpinner = createSpinner('Processing claim...').start();

        try {
          const txHash = await manager.claim(campaign);
          claimSpinner.stop();

          logSuccess('Funds claimed successfully!');
          console.log(`Transaction: ${chalk.blue(txHash)}`);
          console.log(`Amount Claimed: ${chalk.green(claimInfo.creatorAmount)} RBTC`);

        } catch (claimError) {
          claimSpinner.stop();
          
          if (claimError instanceof Error) {
            if (claimError.message.includes('execution reverted')) {
              logError('Claim rejected by contract');
              logInfo('Campaign state may have changed since last check');
            } else if (claimError.message.includes('insufficient funds')) {
              logError('Contract has insufficient funds');
            } else {
              logError(`Claim failed: ${claimError.message}`);
            }
          } else {
            logError(`Claim failed: ${claimError}`);
          }
          
          process.exit(1);
        }

      } catch (infoError) {
        spinner.stop();
        logError(`Failed to check claim eligibility: ${infoError}`);
        process.exit(1);
      }

    } catch (error) {
      logError(`Claim error: ${error}`);
      process.exit(1);
    }
  });
