import { Command } from 'commander';
import chalk from 'chalk';
import { table } from 'table';
import { ContractManager } from '../lib/contract';
import { config } from '../lib/config';
import { 
  logSuccess, 
  logError, 
  logInfo, 
  createSpinner, 
  getPrivateKeyFromEnv,
  formatAddress,
  formatTime,
  formatTimeRemaining,
  formatCampaignStatus,
  parseTimeInput,
  validateEthAmount,
  isValidEthereumAddress,
  confirmAction 
} from '../lib/utils';

export const campaignCommand = new Command('campaign')
  .description('Manage AON campaigns')
  .addCommand(
    new Command('create')
      .description('Create a new AON campaign')
      .requiredOption('-c, --creator <address>', 'Creator address')
      .requiredOption('-g, --goal <amount>', 'Funding goal in RBTC (e.g., "10" or "10 ether")')
      .requiredOption('-d, --duration <duration>', 'Campaign duration (e.g., "30 days", "2 weeks")')
      .option('-w, --claim-window <duration>', 'Claim/refund window duration', '7 days')
      .option('-n, --network <network>', 'Network to use', 'local')
      .option('-k, --private-key <key>', 'Private key (or use PRIVATE_KEY env var)')
      .option('-y, --yes', 'Skip confirmation prompts')
      .action(async (options) => {
        try {
          // Validate inputs
          if (!isValidEthereumAddress(options.creator)) {
            logError('Invalid creator address');
            process.exit(1);
          }

          const goal = validateEthAmount(options.goal);
          const duration = parseTimeInput(options.duration);
          const claimWindow = parseTimeInput(options.claimWindow);

          const privateKey = options.privateKey || getPrivateKeyFromEnv();
          if (!privateKey) {
            logError('Private key required for campaign creation');
            process.exit(1);
          }

          // Display campaign details
          console.log(chalk.blue('Campaign Configuration:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Creator: ${chalk.green(options.creator)}`);
          console.log(`Goal: ${chalk.green(goal)} RBTC`);
          console.log(`Duration: ${chalk.green(options.duration)}`);
          console.log(`Claim Window: ${chalk.green(options.claimWindow)}`);
          console.log(`Network: ${chalk.green(config.getNetwork(options.network).name)}`);

          if (!options.yes) {
            const shouldCreate = await confirmAction('\nCreate campaign?');
            if (!shouldCreate) {
              logInfo('Campaign creation cancelled');
              return;
            }
          }

          const spinner = createSpinner('Creating campaign...').start();

          const globalOptions = options.parent?.opts() || {};
          const manager = new ContractManager(options.network, privateKey, globalOptions.rpcUrl);
          const campaignAddress = await manager.createCampaign(
            options.creator,
            goal,
            duration,
            claimWindow
          );

          spinner.stop();

          logSuccess('Campaign created successfully!');
          console.log(`Campaign Address: ${chalk.blue(campaignAddress)}`);
          logInfo('You can now view details with: aon-cli campaign info ' + campaignAddress);

        } catch (error) {
          logError(`Failed to create campaign: ${error}`);
          process.exit(1);
        }
      })
  )
  .addCommand(
    new Command('info')
      .description('Get detailed information about a campaign')
      .argument('<address>', 'Campaign contract address')
      .option('-n, --network <network>', 'Network to use', 'local')
      .action(async (address, options) => {
        try {
          if (!isValidEthereumAddress(address)) {
            logError('Invalid campaign address');
            process.exit(1);
          }

          const spinner = createSpinner('Fetching campaign information...').start();

          const globalOptions = options.parent?.opts() || {};
          const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
          const info = await manager.getCampaignInfo(address);

          spinner.stop();

          console.log(chalk.blue('Campaign Information:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Address: ${chalk.green(info.address)}`);
          console.log(`Creator: ${chalk.green(info.creator)}`);
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
          
          console.log('\nCampaign State:');
          console.log(`  Goal Reached: ${info.goalReached ? chalk.green('Yes') : chalk.red('No')}`);
          console.log(`  Successful: ${info.isSuccessful ? chalk.green('Yes') : chalk.red('No')}`);
          console.log(`  Failed: ${info.isFailed ? chalk.red('Yes') : chalk.green('No')}`);
          console.log(`  Unclaimed: ${info.isUnclaimed ? chalk.yellow('Yes') : chalk.green('No')}`);

        } catch (error) {
          logError(`Failed to fetch campaign info: ${error}`);
          process.exit(1);
        }
      })
  )
  .addCommand(
    new Command('list')
      .description('List campaigns (requires event indexing - simplified version)')
      .option('-n, --network <network>', 'Network to use', 'local')
      .action(async (options) => {
        logInfo('Campaign listing requires event indexing which is not implemented in this CLI version.');
        logInfo('To view a specific campaign, use: aon-cli campaign info <address>');
        logInfo('You can find campaign addresses from deployment logs or block explorers.');
      })
  )
  .addCommand(
    new Command('cancel')
      .description('Cancel a campaign (creator or factory owner only)')
      .argument('<address>', 'Campaign contract address')
      .option('-n, --network <network>', 'Network to use', 'local')
      .option('-k, --private-key <key>', 'Private key (or use PRIVATE_KEY env var)')
      .option('-y, --yes', 'Skip confirmation prompts')
      .action(async (address, options) => {
        try {
          if (!isValidEthereumAddress(address)) {
            logError('Invalid campaign address');
            process.exit(1);
          }

          const privateKey = options.privateKey || getPrivateKeyFromEnv();
          if (!privateKey) {
            logError('Private key required for campaign cancellation');
            process.exit(1);
          }

          // Get campaign info first
          const globalOptions = options.parent?.opts() || {};
          const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
          const info = await manager.getCampaignInfo(address);

          console.log(chalk.blue('Campaign to Cancel:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Address: ${chalk.green(info.address)}`);
          console.log(`Creator: ${chalk.green(info.creator)}`);
          console.log(`Goal: ${chalk.green(info.goal)} RBTC`);
          console.log(`Raised: ${chalk.green(info.balance)} RBTC`);
          console.log(`Status: ${formatCampaignStatus(info.status)}`);

          if (!options.yes) {
            const shouldCancel = await confirmAction('\nCancel this campaign?');
            if (!shouldCancel) {
              logInfo('Campaign cancellation cancelled');
              return;
            }
          }

          const spinner = createSpinner('Cancelling campaign...').start();

          const managerWithSigner = new ContractManager(options.network, privateKey, globalOptions.rpcUrl);
          const txHash = await managerWithSigner.cancel(address);

          spinner.stop();

          logSuccess('Campaign cancelled successfully!');
          console.log(`Transaction: ${chalk.blue(txHash)}`);

        } catch (error) {
          logError(`Failed to cancel campaign: ${error}`);
          process.exit(1);
        }
      })
  );
