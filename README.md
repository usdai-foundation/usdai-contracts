# USDai Contracts

## Usage

Clone:

```shell
$ git clone --recursive https://github.com/metastreet-labs/metastreet-usdai-contracts.git
```

Build:

```shell
$ forge build
```

Test:

```shell
$ FOUNDRY_OUT=$(pwd)/externalOut forge build --root lib/usdai-loan-router-contracts
$ forge test
```

## Update Submodules

```shell
$ git submodule deinit --force .
$ git submodule update --init --recursive
```

## License

USDai Contracts are primarily BUSL-1.1 [licensed](LICENSE). Interfaces are MIT licensed.
