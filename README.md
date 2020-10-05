# Dex2 development repo

## How to install

```
npm install
```

## How to run all tests

```
npx buidler test-solidity
```

#### What you an do

- Use Buidler's `console.log` in contracts for debugging; those logs survive transaction revert. More in [Buidler's documentation](https://buidler.dev/buidler-evm/#console-log). Example:

```
string memory s = "Hello";
uint n = 31;
console.log("Message %s number %d",s,d);
```

- Run test for a specific contract and show all events of non-reverted transactions. Example:

```
npx buidler test-solidity Dex --show-events
```

- See a Solidity stack trace on reverts

#### More on tests

See [`Greeter.sol`](contracts/Greeter.sol). To test a contract `C`, create a contract `C_Test`. It should probably inherit [`Test`](contracts/Test.sol). To see how it all works, see [`test_solidity.js`](lib/test_solidity.js).

[Buidler](https://buidler.dev) is a development framework for Ethereum. It includes an [EVM interpreter](https://buidler.dev/buidler-evm) with special hooks for

- interpreting `console.log`-type statements
- displaying Solidity stack traces

It has an extendable task system; this repo adds a `test-solidity` task. Run `npx buidler help test-solidity` for available options. The task itself is defined in [buidler.config.js](./buidler.config.js).
