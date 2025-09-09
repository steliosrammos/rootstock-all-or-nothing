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
  formatAddress 
} from '../lib/utils';

export const accountsCommand = new Command('accounts')
  .description('List available accounts on the network')
  .option('-n, --network <network>', 'Network to use', 'local')
  .option('--with-balances', 'Include RBTC balances (slower)')
  .action(async (options) => {
    try {
      const spinner = createSpinner('Fetching accounts...').start();

      const globalOptions = options.parent?.opts() || {};
      const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
      const accounts = await manager.getAccounts();

      if (accounts.length === 0) {
        spinner.stop();
        logInfo('No accounts available on this network');
        logInfo('For local development, ensure Anvil is running with: aon-cli setup start');
        return;
      }

      let balances: string[] = [];
      
      if (options.withBalances) {
        spinner.text = 'Fetching account balances...';
        balances = await Promise.all(
          accounts.map(account => manager.getBalance(account))
        );
      }

      spinner.stop();

      const network = config.getNetwork(options.network, globalOptions.rpcUrl);
      console.log(chalk.blue(`Available Accounts (${network.name}):`));
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (options.withBalances) {
        const tableData = [
          ['Index', 'Address', 'Balance (RBTC)'],
          ...accounts.map((account, index) => [
            chalk.gray(index.toString()),
            chalk.green(account),
            chalk.yellow(parseFloat(balances[index]).toFixed(4))
          ])
        ];

        console.log(table(tableData, {
          border: {
            topBody: '─',
            topJoin: '┬',
            topLeft: '┌',
            topRight: '┐',
            bottomBody: '─',
            bottomJoin: '┴',
            bottomLeft: '└',
            bottomRight: '┘',
            bodyLeft: '│',
            bodyRight: '│',
            bodyJoin: '│',
            joinBody: '─',
            joinLeft: '├',
            joinRight: '┤',
            joinJoin: '┼'
          },
          columns: {
            0: { width: 8, alignment: 'center' },
            1: { width: 44 },
            2: { width: 15, alignment: 'right' }
          }
        }));
      } else {
        accounts.forEach((account, index) => {
          console.log(`${chalk.gray(index.toString().padStart(2))}: ${chalk.green(account)}`);
        });
      }

      console.log(`\nTotal accounts: ${chalk.blue(accounts.length)}`);
      
      if (!options.withBalances) {
        logInfo('Use --with-balances to see RBTC balances');
      }

      logInfo('Use these addresses with --private-key or set PRIVATE_KEY environment variable');

    } catch (error) {
      logError(`Failed to fetch accounts: ${error}`);
      
      if (error instanceof Error && error.message.includes('network')) {
        logInfo('Check network connectivity and RPC URL');
      }
      
      process.exit(1);
    }
  });
