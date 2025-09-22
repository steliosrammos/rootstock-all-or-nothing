export interface NetworkConfig {
  name: string;
  rpcUrl: string;
  chainId: number;
  contracts?: {
    factory?: string;
    implementation?: string;
    goalStrategy?: string;
  };
}

export interface CLIConfig {
  networks: Record<string, NetworkConfig>;
  defaultNetwork: string;
  defaultPrivateKey?: string;
}

export interface CampaignInfo {
  address: string;
  creator: string;
  goal: string;
  endTime: number;
  status: number;
  balance: string;
  totalFee: string;
  totalTip: string;
  claimOrRefundWindow: number;
  goalReached: boolean;
  isSuccessful: boolean;
  isFailed: boolean;
  isUnclaimed: boolean;
}

export interface ContributionInfo {
  contributor: string;
  amount: string;
  canRefund: boolean;
  refundAmount: string;
}

export interface DeploymentResult {
  factory: string;
  implementation: string;
  goalStrategy: string;
  deployer: string;
  network: string;
  blockNumber: number;
  gasUsed: string;
}

export enum CampaignStatus {
  Active = 0,
  Cancelled = 1,
  Claimed = 2
}

export interface SignatureData {
  contributor?: string;
  creator?: string;
  swapContract: string;
  amount: string;
  nonce: string;
  deadline: number;
  signature: string;
}
