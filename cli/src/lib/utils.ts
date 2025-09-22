import chalk from 'chalk';
import ora from 'ora';
import { formatEther, parseEther, isAddress } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

export function formatAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatEtherValue(wei: string | bigint): string {
  return `${formatEther(BigInt(wei))} RBTC`;
}

export function formatTime(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString();
}

export function parseTimeInput(input: string): number {
  const timeUnits: Record<string, number> = {
    s: 1,
    sec: 1,
    second: 1,
    seconds: 1,
    m: 60,
    min: 60,
    minute: 60,
    minutes: 60,
    h: 3600,
    hr: 3600,
    hour: 3600,
    hours: 3600,
    d: 86400,
    day: 86400,
    days: 86400,
    w: 604800,
    week: 604800,
    weeks: 604800,
  };

  const match = input.match(/^(\d+)\s*(.*)?$/);
  if (!match) {
    throw new Error('Invalid time format. Use format like "30 days", "2 hours", "5m"');
  }

  const value = parseInt(match[1]);
  const unit = (match[2] || 'seconds').toLowerCase();

  const multiplier = timeUnits[unit];
  if (!multiplier) {
    throw new Error(`Unknown time unit: ${unit}. Supported: ${Object.keys(timeUnits).join(', ')}`);
  }

  return value * multiplier;
}

export function formatDuration(seconds: number): string {
  const units = [
    { name: 'day', seconds: 86400 },
    { name: 'hour', seconds: 3600 },
    { name: 'minute', seconds: 60 },
    { name: 'second', seconds: 1 },
  ];

  for (const unit of units) {
    if (seconds >= unit.seconds) {
      const value = Math.floor(seconds / unit.seconds);
      const remainder = seconds % unit.seconds;
      
      let result = `${value} ${unit.name}${value !== 1 ? 's' : ''}`;
      
      if (remainder > 0 && unit.seconds > 60) {
        result += ` ${formatDuration(remainder)}`;
      }
      
      return result;
    }
  }
  
  return '0 seconds';
}

export function isValidEthereumAddress(address: string): boolean {
  return isAddress(address);
}

export function isValidPrivateKey(privateKey: string): boolean {
  try {
    privateKeyToAccount(`0x${privateKey.replace('0x', '')}` as `0x${string}`);
    return true;
  } catch {
    return false;
  }
}

export async function confirmAction(message: string): Promise<boolean> {
  const inquirer = await import('inquirer');
  const { confirm } = await inquirer.default.prompt([
    {
      type: 'confirm',
      name: 'confirm',
      message,
      default: false,
    },
  ]);
  return confirm;
}

export function createSpinner(text: string) {
  return ora(text);
}

export function logSuccess(message: string): void {
  console.log(chalk.green('✓'), message);
}

export function logError(message: string): void {
  console.log(chalk.red('✗'), message);
}

export function logWarning(message: string): void {
  console.log(chalk.yellow('⚠'), message);
}

export function logInfo(message: string): void {
  console.log(chalk.blue('ℹ'), message);
}

export function formatCampaignStatus(status: number): string {
  switch (status) {
    case 0:
      return chalk.blue('Active');
    case 1:
      return chalk.yellow('Cancelled');
    case 2:
      return chalk.green('Claimed');
    default:
      return chalk.gray('Unknown');
  }
}

export function formatTimeRemaining(endTime: number): string {
  const now = Math.floor(Date.now() / 1000);
  const remaining = endTime - now;
  
  if (remaining <= 0) {
    return chalk.red('Ended');
  }
  
  return chalk.green(formatDuration(remaining));
}

export function validateEthAmount(amount: string, allowZero: boolean = false): string {
  try {
    const parsed = parseEther(amount);
    if (!allowZero && parsed <= 0n) {
      throw new Error('Amount must be greater than 0');
    }
    if (parsed < 0n) {
      throw new Error('Amount cannot be negative');
    }
    return formatEther(parsed);
  } catch (error) {
    throw new Error(`Invalid RBTC amount: ${error}`);
  }
}

export function getPrivateKeyFromEnv(): string | undefined {
  return process.env.PRIVATE_KEY || process.env.RSK_DEPLOYMENT_PRIVATE_KEY;
}

export function formatGasUsed(gasUsed: string): string {
  const gas = BigInt(gasUsed);
  if (gas > 1000000n) {
    return `${(Number(gas) / 1000000).toFixed(2)}M gas`;
  } else if (gas > 1000n) {
    return `${(Number(gas) / 1000).toFixed(2)}K gas`;
  }
  return `${gas} gas`;
}
