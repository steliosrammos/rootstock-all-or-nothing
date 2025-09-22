import { defineConfig } from '@wagmi/cli'
import { foundry } from '@wagmi/cli/plugins'

export default defineConfig({
  out: 'src/generated.ts',
  contracts: [],
  plugins: [
    foundry({
      project: '../',
      deployments: {
        Factory: {
          31: '0x', // RSK Testnet - will be populated after deployment
          30: '0x', // RSK Mainnet - will be populated after deployment
          31337: '0x', // Local Anvil - will be populated after deployment
        },
        Aon: {
          31: '0x', // RSK Testnet
          30: '0x', // RSK Mainnet
          31337: '0x', // Local Anvil
        },
        AonGoalReachedNative: {
          31: '0x', // RSK Testnet
          30: '0x', // RSK Mainnet
          31337: '0x', // Local Anvil
        },
      },
    }),
  ],
})
