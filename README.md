## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```



deploy: 
```shell
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

add amount to deployment public key:
```shell
docker exec boltz-anvil cast send --rpc-url http://anvil:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 0x9cCA66b3F0655E8511ff25B8797034B8D99835cC --value 10ether
```

call the contribute method in the aon contract with value:
```shell
cast send 0x55652FF92Dc17a21AD6810Cce2F4703fa2339CAE "contribute(uint256)" 0 --value 879450000000000 --private-key 64b075e4ca5c8f179bcf13ba8743cebcf68c5a86051ac7afefa613332fbd19db --rpc-url http://localhost:8545
```

check if the contract contribute got the balance:
```shell
cast call 0x55652FF92Dc17a21AD6810Cce2F4703fa2339CAE "contributions(address)" 0x3e2e5183f23dbcdedfb5f48813c4208691084aec --rpc-url http://localhost:8545
```