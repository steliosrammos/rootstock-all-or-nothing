import { Command } from 'commander';
import chalk from 'chalk';
import { config } from '../lib/config';
import { logSuccess, logError, logInfo, createSpinner } from '../lib/utils';
import { spawn } from 'child_process';
import { existsSync } from 'fs';
import { resolve } from 'path';

export const setupCommand = new Command('setup')
  .description('Setup and manage local development environment')
  .addCommand(
    new Command('init')
      .description('Initialize CLI configuration')
      .action(async () => {
        try {
          const spinner = createSpinner('Initializing AON CLI configuration...').start();
          
          // Save default config
          config.save();
          
          spinner.stop();
          logSuccess('Configuration initialized successfully');
          logInfo(`Config file created at: ${config.getConfigPath()}`);
          
          console.log('\nDefault networks configured:');
          const networks = config.listNetworks();
          Object.entries(networks).forEach(([name, net]) => {
            const isDefault = name === config.getDefaultNetwork();
            console.log(`  ${isDefault ? '→' : ' '} ${chalk.blue(name)}: ${net.rpcUrl} (Chain ID: ${net.chainId})`);
          });
          
        } catch (error) {
          logError(`Failed to initialize configuration: ${error}`);
          process.exit(1);
        }
      })
  )
  .addCommand(
    new Command('start')
      .description('Start local Anvil node using Docker Compose')
      .option('-d, --detach', 'Run in detached mode')
      .action(async (options) => {
        try {
          const dockerComposePath = resolve(process.cwd(), 'docker-compose.yml');
          
          if (!existsSync(dockerComposePath)) {
            logError('docker-compose.yml not found in current directory');
            logInfo('Run this command from the project root directory or create a docker-compose.yml file');
            process.exit(1);
          }
          
          const spinner = createSpinner('Starting local development environment...').start();
          
          const dockerArgs = ['compose', 'up'];
          if (options.detach) {
            dockerArgs.push('-d');
          }
          
          await new Promise<void>((resolve, reject) => {
            const dockerProcess = spawn('docker', dockerArgs, {
              stdio: options.detach ? 'pipe' : 'inherit',
              cwd: process.cwd(),
            });
            
            dockerProcess.on('close', (code) => {
              if (code === 0) {
                resolve();
              } else {
                reject(new Error(`Docker process exited with code ${code}`));
              }
            });
            
            dockerProcess.on('error', reject);
          });
          
          spinner.stop();
          
          if (options.detach) {
            logSuccess('Local development environment started in detached mode');
            logInfo('Anvil node is running at: http://localhost:8545');
            logInfo('To stop: aon-cli setup stop');
          } else {
            logSuccess('Local development environment started');
          }
          
        } catch (error) {
          logError(`Failed to start development environment: ${error}`);
          process.exit(1);
        }
      })
  )
  .addCommand(
    new Command('stop')
      .description('Stop local development environment')
      .action(async () => {
        try {
          const spinner = createSpinner('Stopping local development environment...').start();
          
          await new Promise<void>((resolve, reject) => {
            const dockerProcess = spawn('docker', ['compose', 'down'], {
              stdio: 'pipe',
              cwd: process.cwd(),
            });
            
            dockerProcess.on('close', (code) => {
              if (code === 0) {
                resolve();
              } else {
                reject(new Error(`Docker process exited with code ${code}`));
              }
            });
            
            dockerProcess.on('error', reject);
          });
          
          spinner.stop();
          logSuccess('Local development environment stopped');
          
        } catch (error) {
          logError(`Failed to stop development environment: ${error}`);
          process.exit(1);
        }
      })
  )
  .addCommand(
    new Command('status')
      .description('Check status of development environment')
      .option('-n, --network <network>', 'Network to check status for', 'local')
      .action(async (options) => {
        try {
          const { ContractManager } = await import('../lib/contract');
          const globalOptions = options.parent?.parent?.opts() || {};
          const manager = new ContractManager(options.network, undefined, globalOptions.rpcUrl);
          
          const network = config.getNetwork(options.network, globalOptions.rpcUrl);
          
          console.log(chalk.blue('Development Environment Status:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`Network: ${chalk.green(network.name)}`);
          console.log(`RPC URL: ${network.rpcUrl}`);
          console.log(`Chain ID: ${network.chainId}`);
          
          if (globalOptions.rpcUrl) {
            console.log(`${chalk.yellow('⚠')} Using custom RPC URL - Anvil management disabled`);
          }
          
          try {
            const accounts = await manager.getAccounts();
            logSuccess(`Node is accessible (${accounts.length} accounts available)`);
            
            // Check for deployed contracts
            const factoryAddress = config.getNetworkContract(options.network, 'factory');
            if (factoryAddress) {
              logSuccess(`Factory contract deployed at: ${factoryAddress}`);
            } else {
              logInfo(`No contracts deployed yet. Run: aon-cli deploy${options.network !== 'local' ? ` --network ${options.network}` : ''}`);
            }
            
          } catch (error) {
            logError('Node is not accessible');
            if (config.shouldManageAnvil(options.network, globalOptions.rpcUrl)) {
              logInfo('Start the local node with: aon-cli setup start');
            } else {
              logInfo(`Check that the RPC URL ${network.rpcUrl} is accessible`);
            }
          }
          
        } catch (error) {
          logError(`Failed to check status: ${error}`);
        }
      })
  )
  .addCommand(
    new Command('env')
      .description('Show environment configuration and available private keys')
      .action(async () => {
        try {
          console.log(chalk.blue('Environment Configuration:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          
          // Check for .env files
          const fs = require('fs');
          const path = require('path');
          
          const envPaths = [
            path.resolve(process.cwd(), '.env'),
            path.resolve(process.cwd(), '../.env'),
            path.resolve(process.cwd(), '../../.env'),
          ];
          
          let envFileFound = false;
          for (const envPath of envPaths) {
            if (fs.existsSync(envPath)) {
              console.log(`✅ Environment file found: ${chalk.green(envPath)}`);
              envFileFound = true;
              break;
            }
          }
          
          if (!envFileFound) {
            console.log(`❌ No .env file found in:`);
            envPaths.forEach(path => console.log(`   ${chalk.gray(path)}`));
            console.log('');
            logInfo('Create a .env file with your private keys for easier usage');
          }
          
          console.log('');
          console.log(chalk.blue('Available Private Keys:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          
          const privateKey = process.env.PRIVATE_KEY;
          const rskPrivateKey = process.env.RSK_DEPLOYMENT_PRIVATE_KEY;
          
          if (privateKey) {
            console.log(`✅ PRIVATE_KEY: ${chalk.green('Available')} (${privateKey.slice(0, 6)}...${privateKey.slice(-4)})`);
          } else {
            console.log(`❌ PRIVATE_KEY: ${chalk.red('Not set')}`);
          }
          
          if (rskPrivateKey) {
            console.log(`✅ RSK_DEPLOYMENT_PRIVATE_KEY: ${chalk.green('Available')} (${rskPrivateKey.slice(0, 6)}...${rskPrivateKey.slice(-4)})`);
          } else {
            console.log(`❌ RSK_DEPLOYMENT_PRIVATE_KEY: ${chalk.red('Not set')}`);
          }
          
          console.log('');
          console.log(chalk.blue('Usage:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          
          if (privateKey || rskPrivateKey) {
            console.log('With environment variables set, you can run commands without --private-key:');
            console.log(`  ${chalk.green('aon-cli deploy')}`);
            console.log(`  ${chalk.green('aon-cli campaign create --creator 0x... --goal "10" --duration "30 days"')}`);
            console.log(`  ${chalk.green('aon-cli contribute CAMPAIGN_ADDRESS --amount "1"')}`);
          } else {
            console.log('Set up environment variables for easier usage:');
            console.log('');
            console.log('Create a .env file in your project root:');
            console.log(chalk.gray('  PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'));
            console.log(chalk.gray('  RSK_DEPLOYMENT_PRIVATE_KEY=0x...'));
            console.log('');
            console.log('Then you can run commands without --private-key flag');
          }
          
          console.log('');
          console.log(chalk.blue('Default Anvil Accounts:'));
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log('Account 0 (10,000 RBTC):');
          console.log(`  Address: ${chalk.green('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266')}`);
          console.log(`  Private: ${chalk.gray('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80')}`);
          console.log('Account 1 (10,000 RBTC):');
          console.log(`  Address: ${chalk.green('0x70997970C51812dc3A010C7d01b50e0d17dc79C8')}`);
          console.log(`  Private: ${chalk.gray('0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d')}`);
          
        } catch (error) {
          logError(`Failed to show environment info: ${error}`);
        }
      })
  );
