import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import { homedir } from 'os';
import yaml from 'yaml';
import { CLIConfig, NetworkConfig } from '../types';

const CONFIG_DIR = resolve(homedir(), '.aon-cli');
const CONFIG_FILE = resolve(CONFIG_DIR, 'config.yaml');

const DEFAULT_CONFIG: CLIConfig = {
  networks: {
    local: {
      name: 'Local Anvil',
      rpcUrl: 'http://localhost:8545',
      chainId: 31337,
    },
    'rsk-testnet': {
      name: 'RSK Testnet',
      rpcUrl: 'https://public-node.testnet.rsk.co',
      chainId: 31,
    },
    'rsk-mainnet': {
      name: 'RSK Mainnet',
      rpcUrl: 'https://public-node.rsk.co',
      chainId: 30,
    },
  },
  defaultNetwork: 'local',
};

export class Config {
  private config: CLIConfig;

  constructor() {
    this.config = this.loadConfig();
  }

  private loadConfig(): CLIConfig {
    if (!existsSync(CONFIG_FILE)) {
      return { ...DEFAULT_CONFIG };
    }

    try {
      const content = readFileSync(CONFIG_FILE, 'utf8');
      const loaded = yaml.parse(content) as CLIConfig;
      
      // Merge with defaults to ensure all properties exist
      return {
        ...DEFAULT_CONFIG,
        ...loaded,
        networks: {
          ...DEFAULT_CONFIG.networks,
          ...loaded.networks,
        },
      };
    } catch (error) {
      console.warn('Failed to load config, using defaults:', error);
      return { ...DEFAULT_CONFIG };
    }
  }

  save(): void {
    try {
      // Ensure config directory exists
      const fs = require('fs');
      if (!fs.existsSync(CONFIG_DIR)) {
        fs.mkdirSync(CONFIG_DIR, { recursive: true });
      }

      const content = yaml.stringify(this.config);
      writeFileSync(CONFIG_FILE, content, 'utf8');
    } catch (error) {
      throw new Error(`Failed to save config: ${error}`);
    }
  }

  getNetwork(name?: string, customRpcUrl?: string): NetworkConfig {
    const networkName = name || this.config.defaultNetwork;
    const network = this.config.networks[networkName];
    
    if (!network) {
      throw new Error(`Network '${networkName}' not found in config`);
    }
    
    // If custom RPC URL is provided, create a temporary network config
    if (customRpcUrl) {
      return {
        ...network,
        rpcUrl: customRpcUrl,
        name: `${network.name} (Custom RPC)`,
      };
    }
    
    return network;
  }

  isLocalRpcUrl(rpcUrl: string): boolean {
    const localPatterns = [
      /^https?:\/\/localhost/,
      /^https?:\/\/127\.0\.0\.1/,
      /^https?:\/\/0\.0\.0\.0/,
      /^http:\/\/anvil:/,  // Docker container name
    ];
    
    return localPatterns.some(pattern => pattern.test(rpcUrl));
  }

  shouldManageAnvil(networkName: string, customRpcUrl?: string): boolean {
    const network = this.getNetwork(networkName, customRpcUrl);
    
    // Only manage Anvil for local networks with default local URLs
    return networkName === 'local' && 
           !customRpcUrl && 
           this.isLocalRpcUrl(network.rpcUrl);
  }

  setNetworkContract(networkName: string, contractType: string, address: string): void {
    if (!this.config.networks[networkName]) {
      throw new Error(`Network '${networkName}' not found`);
    }

    if (!this.config.networks[networkName].contracts) {
      this.config.networks[networkName].contracts = {};
    }

    this.config.networks[networkName].contracts![contractType as keyof NonNullable<NetworkConfig['contracts']>] = address;
    this.save();
  }

  getNetworkContract(networkName: string, contractType: string): string | undefined {
    const network = this.config.networks[networkName];
    return network?.contracts?.[contractType as keyof NonNullable<NetworkConfig['contracts']>];
  }

  listNetworks(): Record<string, NetworkConfig> {
    return this.config.networks;
  }

  setDefaultNetwork(networkName: string): void {
    if (!this.config.networks[networkName]) {
      throw new Error(`Network '${networkName}' not found`);
    }
    
    this.config.defaultNetwork = networkName;
    this.save();
  }

  getDefaultNetwork(): string {
    return this.config.defaultNetwork;
  }

  addNetwork(name: string, config: NetworkConfig): void {
    this.config.networks[name] = config;
    this.save();
  }

  removeNetwork(name: string): void {
    if (name === this.config.defaultNetwork) {
      throw new Error('Cannot remove the default network');
    }
    
    delete this.config.networks[name];
    this.save();
  }

  getConfigPath(): string {
    return CONFIG_FILE;
  }
}

export const config = new Config();
