#!/usr/bin/env node

import { Command } from 'commander';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { resolve } from 'path';

// Load environment variables from .env file
// Try multiple locations to handle both development and global installation
dotenv.config({ path: resolve(process.cwd(), '.env') }); // Current directory
dotenv.config({ path: resolve(process.cwd(), '../.env') }); // Parent directory
dotenv.config({ path: resolve(__dirname, '../.env') }); // Relative to built CLI
dotenv.config({ path: resolve(__dirname, '../../.env') }); // CLI source directory
import { deployCommand } from './commands/deploy';
import { campaignCommand } from './commands/campaign';
import { contributeCommand } from './commands/contribute';
import { refundCommand } from './commands/refund';
import { claimCommand } from './commands/claim';
import { setupCommand } from './commands/setup';
import { accountsCommand } from './commands/accounts';
import { balanceCommand } from './commands/balance';

const program = new Command();

program
  .name('aon-cli')
  .description('CLI tool for interacting with AON (All-Or-Nothing) crowdfunding contracts')
  .version('1.0.0')
  .option('--rpc-url <url>', 'Custom RPC URL (overrides network configuration)');

// Add styling to help text
program.configureHelp({
  sortSubcommands: true,
  subcommandTerm: (cmd) => chalk.blue(cmd.name()),
  optionTerm: (option) => chalk.green(option.flags),
});

// Environment setup commands
program.addCommand(setupCommand);

// Contract deployment commands
program.addCommand(deployCommand);

// Campaign management commands
program.addCommand(campaignCommand);

// Contribution operations
program.addCommand(contributeCommand);
program.addCommand(refundCommand);
program.addCommand(claimCommand);

// Utility commands
program.addCommand(accountsCommand);
program.addCommand(balanceCommand);

// Global error handler
process.on('uncaughtException', (error) => {
  console.error(chalk.red('Uncaught Exception:'), error.message);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error(chalk.red('Unhandled Rejection:'), reason);
  process.exit(1);
});

// Parse command line arguments
program.parse();
