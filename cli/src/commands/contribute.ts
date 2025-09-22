import { Command } from 'commander';
import chalk from 'chalk';
import { ContractManager } from '../lib/contract';
import { config } from '../lib/config';
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

export const contributeCommand = new Command('contribute')
  .description('Contribute to an AON campaign')
  .argument('<campaign>', 'Campaign contract address')
  .requiredOption('-a, --amount <amount>', 'Amount to contribute in RBTC')
  .option('-f, --fee <amount>', 'Platform fee in RBTC', '0')
  .option('-t, --tip <amount>', 'Tip amount in RBTC (optional)', '0')
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

      const amount = validateEthAmount(options.amount);
      const fee = validateEthAmount(options.fee, true); // Allow zero for fees
      const tip = validateEthAmount(options.tip, true); // Allow zero for tips

      const privateKey = options.privateKey || getPrivateKeyFromEnv();
      if (!privateKey) {
        logError('Private key required for contribution');
        process.exit(1);
      }

      const globalOptions = options.parent?.opts() || {};
      const manager = new ContractManager(options.network, privateKey, globalOptions.rpcUrl);
      const contributor = manager.signer?.address;

      // Get campaign info
      const spinner = createSpinner('Fetching campaign information...').start();
      const info = await manager.getCampaignInfo(campaign);
      spinner.stop();

      // Display contribution details
      console.log(chalk.blue('Contribution Details:'));
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
      console.log(`Creator: ${chalk.green(formatAddress(info.creator))}`);
      console.log(`Goal: ${chalk.green(info.goal)} RBTC`);
      console.log(`Current Raised: ${chalk.green(info.balance)} RBTC`);
      console.log(`Your Contribution: ${chalk.yellow(amount)} RBTC`);
      console.log(`Platform Fee: ${chalk.gray(fee)} RBTC`);
      if (parseFloat(tip) > 0) {
        console.log(`Tip: ${chalk.cyan(tip)} RBTC`);
      }
      console.log(`Total: ${chalk.yellow((parseFloat(amount) + parseFloat(fee) + parseFloat(tip)).toFixed(18))} RBTC`);
      console.log(`Contributor: ${chalk.blue(formatAddress(contributor || 'Unknown'))}`);

      // Check campaign status
      if (info.status !== 0) {
        logError(`Cannot contribute to campaign with status: ${info.status === 1 ? 'Cancelled' : 'Claimed'}`);
        process.exit(1);
      }

      const currentTime = Math.floor(Date.now() / 1000);
      if (currentTime > info.endTime) {
        logError('Campaign has ended');
        process.exit(1);
      }

      if (!options.yes) {
        const shouldContribute = await confirmAction('\nProceed with contribution?');
        if (!shouldContribute) {
          logInfo('Contribution cancelled');
          return;
        }
      }

      const contributionSpinner = createSpinner('Sending contribution...').start();

      try {
        const txHash = await manager.contribute(campaign, amount, fee, tip);
        contributionSpinner.stop();

        logSuccess('Contribution sent successfully!');
        console.log(`Transaction: ${chalk.blue(txHash)}`);
        console.log(`Amount: ${chalk.green(amount)} RBTC`);
        console.log(`Fee: ${chalk.gray(fee)} RBTC`);
        if (parseFloat(tip) > 0) {
          console.log(`Tip: ${chalk.cyan(tip)} RBTC`);
        }

        logInfo('You can check your contribution with: aon-cli contribution info ' + campaign);

      } catch (contributionError) {
        contributionSpinner.stop();
        
        if (contributionError instanceof Error) {
          if (contributionError.message.includes('insufficient funds')) {
            logError('Insufficient funds for contribution');
            logInfo('Ensure your account has enough RBTC for the contribution amount plus gas fees');
          } else if (contributionError.message.includes('execution reverted')) {
            logError('Contribution rejected by contract');
            logInfo('Check campaign status and contribution amount');
          } else if (contributionError.message.includes('TipCannotExceedContributionAmount')) {
            logError('Tip amount cannot exceed or equal contribution amount');
            logInfo('Tip must be less than the contribution amount');
          } else {
            logError(`Contribution failed: ${contributionError.message}`);
          }
        } else {
          logError(`Contribution failed: ${contributionError}`);
        }
        
        process.exit(1);
      }

    } catch (error) {
      logError(`Contribution error: ${error}`);
      process.exit(1);
    }
  })
  .addCommand(
    new Command('info')
      .description('Get contribution information for an address')
      .argument('<campaign>', 'Campaign contract address')
      .argument('<contributor>', 'Contributor address')
      .option('-n, --network <network>', 'Network to use', 'local')
      .action(async (campaign, contributor, options) => {
        try {
          if (!isValidEthereumAddress(campaign)) {
            logError('Invalid campaign address');
            process.exit(1);
          }

          if (!isValidEthereumAddress(contributor)) {
            logError('Invalid contributor address');
            process.exit(1);
          }

          const spinner = createSpinner('Fetching contribution information...').start();

          const globalOptions = options.parent?.opts() || {};
          const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
          const [campaignInfo, contributionInfo] = await Promise.all([
            manager.getCampaignInfo(campaign),
            manager.getContributionInfo(campaign, contributor),
          ]);

          spinner.stop();

          console.log(chalk.blue('Contribution Information:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Campaign: ${chalk.green(formatAddress(campaign))}`);
          console.log(`Contributor: ${chalk.green(formatAddress(contributor))}`);
          console.log(`Amount Contributed: ${chalk.green(contributionInfo.amount)} RBTC`);
          console.log(`Can Refund: ${contributionInfo.canRefund ? chalk.green('Yes') : chalk.red('No')}`);
          console.log(`Refund Amount: ${chalk.yellow(contributionInfo.refundAmount)} RBTC`);

          console.log('\nCampaign Status:');
          console.log(`  Goal: ${chalk.green(campaignInfo.goal)} RBTC`);
          console.log(`  Raised: ${chalk.green(campaignInfo.balance)} RBTC`);
          console.log(`  Status: ${campaignInfo.status === 0 ? chalk.blue('Active') : 
                                   campaignInfo.status === 1 ? chalk.yellow('Cancelled') : 
                                   chalk.green('Claimed')}`);

          if (contributionInfo.canRefund && parseFloat(contributionInfo.refundAmount) > 0) {
            logInfo(`You can refund with: aon-cli refund ${campaign}`);
          }

        } catch (error) {
          logError(`Failed to fetch contribution info: ${error}`);
          process.exit(1);
        }
      })
  );
