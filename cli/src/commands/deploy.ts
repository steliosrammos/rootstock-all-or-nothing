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
  formatAddress,
  formatGasUsed,
  confirmAction 
} from '../lib/utils';

export const deployCommand = new Command('deploy')
  .description('Deploy AON contracts to a network')
  .option('-n, --network <network>', 'Network to deploy to', 'local')
  .option('-k, --private-key <key>', 'Private key for deployment (or use PRIVATE_KEY env var)')
  .option('-y, --yes', 'Skip confirmation prompts')
  .action(async (options) => {
    try {
      const privateKey = options.privateKey || getPrivateKeyFromEnv();
      
      if (!privateKey) {
        logError('Private key required for deployment');
        logInfo('Provide via --private-key option or PRIVATE_KEY environment variable');
        process.exit(1);
      }

      const globalOptions = options.parent?.opts() || {};
      const network = config.getNetwork(options.network, globalOptions.rpcUrl);
      
      console.log(chalk.blue('Deployment Configuration:'));
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Network: ${chalk.green(network.name)}`);
      console.log(`RPC URL: ${network.rpcUrl}`);
      console.log(`Chain ID: ${network.chainId}`);
      
      // Check if contracts already deployed
      const existingFactory = config.getNetworkContract(options.network, 'factory');
      if (existingFactory) {
        console.log(`\n${chalk.yellow('⚠')} Contracts already deployed on this network:`);
        console.log(`Factory: ${existingFactory}`);
        
        if (!options.yes) {
          const shouldContinue = await confirmAction('Deploy new contracts anyway?');
          if (!shouldContinue) {
            logInfo('Deployment cancelled');
            return;
          }
        }
      }
      
      if (!options.yes) {
        const shouldDeploy = await confirmAction('\nProceed with deployment?');
        if (!shouldDeploy) {
          logInfo('Deployment cancelled');
          return;
        }
      }

      const spinner = createSpinner('Deploying contracts...').start();
      
      try {
        const manager = new ContractManager(options.network, privateKey, globalOptions.rpcUrl);
        const result = await manager.deployContracts();
        
        spinner.stop();
        
        console.log(chalk.green('\n✓ Deployment successful!'));
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`Deployer: ${chalk.blue(formatAddress(result.deployer))}`);
        console.log(`Network: ${chalk.green(result.network)}`);
        console.log(`Block: ${chalk.gray(result.blockNumber)}`);
        console.log(`Gas Used: ${chalk.yellow(formatGasUsed(result.gasUsed))}`);
        console.log('');
        console.log('Contract Addresses:');
        console.log(`  Factory:        ${chalk.blue(result.factory)}`);
        console.log(`  Implementation: ${chalk.blue(result.implementation)}`);
        console.log(`  Goal Strategy:  ${chalk.blue(result.goalStrategy)}`);
        
        logSuccess('Contract addresses saved to configuration');
        logInfo('You can now create campaigns with: aon-cli campaign create');
        
      } catch (deployError) {
        spinner.stop();
        
        if (deployError instanceof Error && deployError.message.includes('insufficient funds')) {
          logError('Insufficient funds for deployment');
          logInfo('Ensure your account has enough RBTC for gas fees');
        } else if (deployError instanceof Error && deployError.message.includes('network')) {
          logError('Network connection failed');
          logInfo(`Check that ${network.rpcUrl} is accessible`);
        } else {
          logError(`Deployment failed: ${deployError}`);
        }
        
        process.exit(1);
      }
      
    } catch (error) {
      logError(`Deployment error: ${error}`);
      process.exit(1);
    }
  });
