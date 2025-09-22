import { Command } from 'commander';
import chalk from 'chalk';
import { ContractManager } from '../lib/contract';
import { config } from '../lib/config';
import { 
  logError, 
  logInfo, 
  createSpinner, 
  isValidEthereumAddress,
  formatAddress 
} from '../lib/utils';

export const balanceCommand = new Command('balance')
  .description('Check RBTC balance of an address')
  .argument('<address>', 'Address to check balance for')
  .option('-n, --network <network>', 'Network to use', 'local')
  .action(async (address, options) => {
    try {
      if (!isValidEthereumAddress(address)) {
        logError('Invalid Ethereum address');
        process.exit(1);
      }

      const spinner = createSpinner('Fetching balance...').start();

      const globalOptions = options.parent?.opts() || {};
      const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
      const balance = await manager.getBalance(address);

      spinner.stop();

      console.log(chalk.blue('Balance Information:'));
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Address: ${chalk.green(address)}`);
      console.log(`Short: ${chalk.gray(formatAddress(address))}`);
      const network = config.getNetwork(options.network, globalOptions.rpcUrl);
      console.log(`Network: ${chalk.blue(network.name)}`);
      console.log(`Balance: ${chalk.yellow(parseFloat(balance).toFixed(6))} RBTC`);

      // Show USD value if balance is significant (mock implementation)
      const balanceNum = parseFloat(balance);
      if (balanceNum > 0.001) {
        logInfo('RBTC price data not available in CLI - check external sources for USD value');
      }

    } catch (error) {
      logError(`Failed to fetch balance: ${error}`);
      
      if (error instanceof Error && error.message.includes('network')) {
        logInfo('Check network connectivity and RPC URL');
      }
      
      process.exit(1);
    }
  });
