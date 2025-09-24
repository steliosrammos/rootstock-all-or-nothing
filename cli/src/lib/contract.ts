import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  parseEther, 
  formatEther, 
  getContract,
  parseAbi,
  type PublicClient,
  type WalletClient,
  type Address,
  type Hash,
  type GetContractReturnType,
  type Chain
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil, rootstockTestnet, rootstock } from 'viem/chains';
import { config } from './config';
import { CampaignInfo, ContributionInfo, DeploymentResult, NetworkConfig } from '../types';

// ABI definitions (simplified for CLI usage)
const FACTORY_ABI = parseAbi([
  'function create(address creator, uint256 goalInEther, uint256 durationInSeconds, address goalReachedStrategy, uint256 claimOrRefundWindow) external',
  'function implementation() external view returns (address)',
  'function owner() external view returns (address)',
  'function setImplementation(address _implementation) external',
  'event AonCreated(address contractAddress)',
]);

const AON_ABI = parseAbi([
  'function creator() external view returns (address)',
  'function goal() external view returns (uint256)',
  'function endTime() external view returns (uint256)',
  'function status() external view returns (uint8)',
  'function totalCreatorFee() external view returns (uint256)',
  'function totalContributorFee() external view returns (uint256)',
  'function claimOrRefundWindow() external view returns (uint256)',
  'function contributions(address) external view returns (uint256)',
  'function contribute(uint256 creatorFee, uint256 contributorFee) external payable',
  'function contributeFor(address contributor, uint256 creatorFee, uint256 contributorFee) external payable',
  'function refund(uint256 processingFee) external',
  'function claim() external',
  'function cancel() external',
  'function canRefund(address contributor, uint256 processingFee) external view returns (uint256, uint256)',
  'function canClaim(address) external view returns (uint256, uint256)',
  'function canContribute(uint256) external view returns (bool)',
  'function canCancel() external view returns (bool)',
  'function isSuccessful() external view returns (bool)',
  'function isFailed() external view returns (bool)',
  'function isUnclaimed() external view returns (bool)',
  'function goalReachedStrategy() external view returns (address)',
  'event ContributionReceived(address indexed contributor, uint256 amount)',
  'event ContributionRefunded(address indexed contributor, uint256 amount)',
  'event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount)',
  'event Cancelled()',
  // Error definitions for proper decoding
  'error GoalNotReached()',
  'error GoalReachedAlready()',
  'error InvalidContribution()',
  'error AlreadyClaimed()',
  'error OnlyCreatorCanClaim()',
  'error CannotClaimCancelledContract()',
  'error CannotClaimClaimedContract()',
  'error CannotClaimFailedContract()',
  'error CannotClaimUnclaimedContract()',
  'error CannotRefundZeroContribution()',
  'error CannotRefundClaimedContract()',
  'error InsufficientBalanceForRefund(uint256 balance, uint256 refundAmount, uint256 goal)',
  'error ContributorFeeCannotExceedContributionAmount()',
  'error ProcessingFeeHigherThanRefundAmount(uint256 refundAmount, uint256 processingFee)',
]);

// Chain configurations
const CHAIN_CONFIGS = {
  local: { ...anvil, id: 31337 },
  'rsk-testnet': rootstockTestnet,
  'rsk-mainnet': rootstock,
} as const;

export class ContractManager {
  private publicClient: PublicClient;
  private walletClient?: WalletClient;
  private network: NetworkConfig;
  private networkKey: string;
  private account?: ReturnType<typeof privateKeyToAccount>;
  private chain: Chain;

  constructor(networkName?: string, privateKey?: string, customRpcUrl?: string) {
    this.networkKey = networkName || config.getDefaultNetwork();
    this.network = config.getNetwork(networkName, customRpcUrl);
    
    this.chain = CHAIN_CONFIGS[networkName as keyof typeof CHAIN_CONFIGS] || CHAIN_CONFIGS.local;
    
    this.publicClient = createPublicClient({
      chain: this.chain,
      transport: http(this.network.rpcUrl),
    });
    
    if (privateKey) {
      this.account = privateKeyToAccount(`0x${privateKey.replace('0x', '')}` as `0x${string}`);
      this.walletClient = createWalletClient({
        account: this.account,
        chain: this.chain,
        transport: http(this.network.rpcUrl),
      });
    }
  }

  async getBalance(address: string): Promise<string> {
    const balance = await this.publicClient.getBalance({ 
      address: address as Address 
    });
    return formatEther(balance);
  }

  async getAccounts(): Promise<string[]> {
    try {
      // For Anvil/local development, try to get test accounts
      if (this.networkKey === 'local') {
        // Anvil default accounts (first 10)
        const accounts = [
          '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
          '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC',
          '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
          '0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65',
          '0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc',
          '0x976EA74026E726554dB657fA54763abd0C3a0aa9',
          '0x14dC79964da2C08b23698B3D3cc7Ca32193d9955',
          '0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f',
          '0xa0Ee7A142d267C1f36714E4a8F75612F20a79720',
        ];
        return accounts;
      }
      
      // For production networks, return account if available
      if (this.account) {
        return [this.account.address];
      }
      
      return [];
    } catch (error) {
      if (this.account) {
        return [this.account.address];
      }
      return [];
    }
  }

  async deployContracts(): Promise<DeploymentResult> {
    if (!this.walletClient || !this.account) {
      throw new Error('Wallet client required for deployment');
    }

    // Read contract artifacts from Foundry output
    const fs = require('fs');
    const path = require('path');
    
    const outDir = path.resolve(__dirname, '../../../out');
    
    // Load contract artifacts
    const aonArtifact = JSON.parse(fs.readFileSync(path.join(outDir, 'Aon.sol/Aon.json'), 'utf8'));
    const factoryArtifact = JSON.parse(fs.readFileSync(path.join(outDir, 'Factory.sol/Factory.json'), 'utf8'));
    const goalStrategyArtifact = JSON.parse(fs.readFileSync(path.join(outDir, 'AonGoalReachedNative.sol/AonGoalReachedNative.json'), 'utf8'));

    // Deploy Aon implementation
    const aonHash = await this.walletClient.deployContract({
      abi: aonArtifact.abi,
      bytecode: aonArtifact.bytecode.object,
      args: [],
      account: this.account!,
      chain: this.chain,
    });
    
    const aonReceipt = await this.publicClient.waitForTransactionReceipt({ hash: aonHash });
    const aonAddress = aonReceipt.contractAddress!;

    // Deploy goal strategy
    const goalStrategyHash = await this.walletClient.deployContract({
      abi: goalStrategyArtifact.abi,
      bytecode: goalStrategyArtifact.bytecode.object,
      args: [],
      account: this.account!,
      chain: this.chain,
    });
    
    const goalStrategyReceipt = await this.publicClient.waitForTransactionReceipt({ hash: goalStrategyHash });
    const goalStrategyAddress = goalStrategyReceipt.contractAddress!;

    // Deploy factory
    const factoryHash = await this.walletClient.deployContract({
      abi: factoryArtifact.abi,
      bytecode: factoryArtifact.bytecode.object,
      args: [aonAddress],
      account: this.account!,
      chain: this.chain,
    });
    
    const factoryReceipt = await this.publicClient.waitForTransactionReceipt({ hash: factoryHash });
    const factoryAddress = factoryReceipt.contractAddress!;

    const result: DeploymentResult = {
      factory: factoryAddress,
      implementation: aonAddress,
      goalStrategy: goalStrategyAddress,
      deployer: this.account.address,
      network: this.network.name,
      blockNumber: Number(factoryReceipt.blockNumber),
      gasUsed: factoryReceipt.gasUsed.toString(),
    };

    // Save contract addresses to config
    config.setNetworkContract(this.networkKey, 'factory', result.factory);
    config.setNetworkContract(this.networkKey, 'implementation', result.implementation);
    config.setNetworkContract(this.networkKey, 'goalStrategy', result.goalStrategy);

    return result;
  }

  async createCampaign(
    creator: string,
    goalInEther: string,
    durationInSeconds: number,
    claimOrRefundWindow: number
  ): Promise<string> {
    if (!this.walletClient) {
      throw new Error('Wallet client required for campaign creation');
    }

    const factoryAddress = config.getNetworkContract(this.networkKey, 'factory');
    const goalStrategyAddress = config.getNetworkContract(this.networkKey, 'goalStrategy');
    
    if (!factoryAddress || !goalStrategyAddress) {
      throw new Error('Factory or goal strategy contract not deployed on this network');
    }

    const factory = getContract({
      address: factoryAddress as Address,
      abi: FACTORY_ABI,
      client: { public: this.publicClient, wallet: this.walletClient },
    });

    const goalInWei = parseEther(goalInEther);

    const hash = await factory.write.create([
      creator as Address,
      goalInWei,
      BigInt(durationInSeconds),
      goalStrategyAddress as Address,
      BigInt(claimOrRefundWindow),
    ], {
      account: this.account!,
      chain: this.chain,
    });

    const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
    
    // Find the AonCreated event to get the campaign address
    const logs = await this.publicClient.getLogs({
      address: factoryAddress as Address,
      event: {
        type: 'event',
        name: 'AonCreated',
        inputs: [{ name: 'contractAddress', type: 'address', indexed: false }],
      },
      fromBlock: receipt.blockNumber,
      toBlock: receipt.blockNumber,
    });

    if (logs.length === 0) {
      throw new Error('Campaign creation event not found');
    }

    return logs[0].args.contractAddress as string;
  }

  async getCampaignInfo(campaignAddress: string): Promise<CampaignInfo> {
    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: this.publicClient,
    });

    const [
      creator,
      goal,
      endTime,
      status,
      totalCreatorFee,
      totalContributorFee,
      claimOrRefundWindow,
      balance,
      isSuccessful,
      isFailed,
      isUnclaimed
    ] = await Promise.all([
      campaign.read.creator(),
      campaign.read.goal(),
      campaign.read.endTime(),
      campaign.read.status(),
      campaign.read.totalCreatorFee(),
      campaign.read.totalContributorFee(),
      campaign.read.claimOrRefundWindow(),
      this.publicClient.getBalance({ address: campaignAddress as Address }),
      campaign.read.isSuccessful(),
      campaign.read.isFailed(),
      campaign.read.isUnclaimed(),
    ]);

    return {
      address: campaignAddress,
      creator,
      goal: formatEther(goal),
      endTime: Number(endTime),
      status: Number(status),
      balance: formatEther(balance),
      totalCreatorFee: formatEther(totalCreatorFee),
      totalContributorFee: formatEther(totalContributorFee),
      claimOrRefundWindow: Number(claimOrRefundWindow),
      goalReached: isSuccessful,
      isSuccessful,
      isFailed,
      isUnclaimed,
    };
  }

  async contribute(campaignAddress: string, amountInEther: string, creatorFeeInEther: string = '0', contributorFeeInEther: string = '0'): Promise<Hash> {
    if (!this.walletClient) {
      throw new Error('Wallet client required for contribution');
    }

    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: { public: this.publicClient, wallet: this.walletClient },
    });

    const amount = parseEther(amountInEther);
    const creatorFee = parseEther(creatorFeeInEther);
    const contributorFee = parseEther(contributorFeeInEther);

    const hash = await campaign.write.contribute([creatorFee, contributorFee], { 
      value: amount,
      account: this.account!,
      chain: this.chain,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
    
    return hash;
  }

  async refund(campaignAddress: string, processingFeeInEther: string = '0'): Promise<Hash> {
    if (!this.walletClient) {
      throw new Error('Wallet client required for refund');
    }

    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: { public: this.publicClient, wallet: this.walletClient },
    });

    const processingFee = parseEther(processingFeeInEther);

    const hash = await campaign.write.refund([processingFee], {
      account: this.account!,
      chain: this.chain,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
    
    return hash;
  }

  async claim(campaignAddress: string): Promise<Hash> {
    if (!this.walletClient) {
      throw new Error('Wallet client required for claiming');
    }

    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: { public: this.publicClient, wallet: this.walletClient },
    });

    const hash = await campaign.write.claim({
      account: this.account!,
      chain: this.chain,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
    
    return hash;
  }

  async cancel(campaignAddress: string): Promise<Hash> {
    if (!this.walletClient) {
      throw new Error('Wallet client required for cancellation');
    }

    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: { public: this.publicClient, wallet: this.walletClient },
    });

    const hash = await campaign.write.cancel({
      account: this.account!,
      chain: this.chain,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
    
    return hash;
  }

  async getContributionInfo(campaignAddress: string, contributor: string, processingFeeInEther: string = '0'): Promise<ContributionInfo> {
    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: this.publicClient,
    });
    
    const amount = await campaign.read.contributions([contributor as Address]);
    
    let canRefund = false;
    let refundAmount = 0n;
    
    try {
      const processingFee = parseEther(processingFeeInEther);
      const refundResult = await campaign.read.canRefund([contributor as Address, processingFee]);
      canRefund = refundResult[0] > 0n;
      refundAmount = refundResult[0];
    } catch (error) {
      // Handle revert - contribution cannot be refunded
      canRefund = false;
      refundAmount = 0n;
    }

    return {
      contributor,
      amount: formatEther(amount),
      canRefund,
      refundAmount: formatEther(refundAmount),
    };
  }

  async canClaim(campaignAddress: string, claimer: string): Promise<{ canClaim: boolean; creatorAmount: string; nonce: string; error?: string }> {
    const campaign = getContract({
      address: campaignAddress as Address,
      abi: AON_ABI,
      client: this.publicClient,
    });

    try {
      const result = await campaign.read.canClaim([claimer as Address]);
      return {
        canClaim: true,
        creatorAmount: formatEther(result[0]),
        nonce: result[1].toString(),
      };
    } catch (error: any) {
      // Extract the contract error from the viem error
      let errorMessage = 'Unknown error';
      
      // Check if viem decoded the error name
      const errorName = error?.cause?.data?.errorName || error?.cause?.name || error?.name;
      if (errorName) {
        switch (errorName) {
          case 'OnlyCreatorCanClaim':
            errorMessage = 'Only the campaign creator can claim funds';
            break;
          case 'CannotClaimCancelledContract':
            errorMessage = 'Cannot claim from cancelled campaign';
            break;
          case 'AlreadyClaimed':
            errorMessage = 'Funds have already been claimed';
            break;
          case 'CannotClaimFailedContract':
            errorMessage = 'Cannot claim from failed campaign';
            break;
          case 'CannotClaimUnclaimedContract':
            errorMessage = 'Claim window has expired';
            break;
          case 'GoalNotReached':
            errorMessage = 'Campaign goal has not been reached';
            break;
          default:
            errorMessage = `Contract error: ${error.name}`;
        }
      } else {
        // Fallback to string matching for older error formats
        const errorString = error?.message || error?.details || JSON.stringify(error);
        if (errorString.includes('OnlyCreatorCanClaim')) {
          errorMessage = 'Only the campaign creator can claim funds';
        } else if (errorString.includes('CannotClaimCancelledContract')) {
          errorMessage = 'Cannot claim from cancelled campaign';
        } else if (errorString.includes('AlreadyClaimed')) {
          errorMessage = 'Funds have already been claimed';
        } else if (errorString.includes('CannotClaimFailedContract')) {
          errorMessage = 'Cannot claim from failed campaign';
        } else if (errorString.includes('CannotClaimUnclaimedContract')) {
          errorMessage = 'Claim window has expired';
        } else if (errorString.includes('GoalNotReached')) {
          errorMessage = 'Campaign goal has not been reached';
        }
      }
      
      return {
        canClaim: false,
        creatorAmount: '0',
        nonce: '0',
        error: errorMessage,
      };
    }
  }

  get signer() {
    return this.account;
  }
}