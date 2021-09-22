# mangrove.js

A JavaScript library for Mangrove. Wraps around [Ethers.js](https://github.com/ethers-io/ethers.js/). Works in the **web browser** and **Node.js**.

This SDK is in **open beta**, and is constantly under development. **USE AT YOUR OWN RISK**.

## Install / Import

Web Browser

- TODO Push to npm once ready

```html
<script type="text/javascript" src="https://cdn.jsdelivr.net/npm/..."></script>

<script type="text/javascript">
  window.Mangrove; // or `Mangrove`
</script>
```

Node.js

```
npm install ...
```

```js
const { Mangrove } = require("...");

// or, when using ES6

import { Mangrove } from "...";
```

## Usage

```js
const main = async () => {
  // TODO add rinkeby address
  const mgv = await Mangrove.connect("rinkeby");

  // Connect to ETHUSDC market
  const market = mgv.market({ base: "ETH", quote: "USDC" });

  // Buy ETH with USDC
  market.buy({ volume: 2.1, price: 3700 });
  market.sell({ volume: 1.1, price: 3750 });

  // Read orderbook
  market.book();
  /*
    Returns
    {
      asks: [
        {id: 3, price: 3700, volume: 4, ...},
        {id: 56, price: 3701, volume: 7.12, ...}
      ],
      bids: [
        {id: 811, price: 3600, volume: 1.23, ...},
        {id: 80, price: 3550, volume: 1.11, ...}
      ]
    }
  */

  // Subscribe to orderbook
  market.subscribe((event, utils) => {
    /* `event` is an offer write, failure, success, or cancel */
    console.log(utils.book());
    /* Prints the updated book, same format as `market.book()` */
  });
};

main().catch(console.error);
```

## More Code Examples

See the docblock comments above each function definition or the official [mangrove.js Documentation](TODO).

- TODO put documentation online

## Instance Creation

The following are valid Ethereum providers for initialization of the SDK.

```js
mgv = await Mangrove.connect(window.ethereum); // web browser

mgv = await Mangrove.connect('http://127.0.0.1:8545'); // HTTP provider

mgv = await Mangrove.connect(); // Uses Ethers.js fallback mainnet (for testing only)

mgv = await Mangrove.connect('rinkeby'); // Uses Ethers.js fallback (for testing only)

// Init with private key (server side)
mgv = await Mangrove.connect('https://mainnet.infura.io/v3/_your_project_id_', {
  privateKey: '0x_your_private_key_', // preferably with environment variable
});

// Init with HD mnemonic (server side)
mgv = await Mangrove.connect('mainnet' {
  mnemonic: 'clutch captain shoe...', // preferably with environment variable
});
```

## Constants and Contract Addresses

Names of contracts, their addresses and token decimals can be found in `/src/constants.ts`. ABIs and typechain-generated types are in `types/typechain/`. Addresses, for all networks, can be easily fetched using the `getAddress` function, combined with contract name constants.

```js
cUsdtAddress = Mangrove.getAddress("USDC");
// Mainnet USDC address. Second parameter can be a network like 'rinkeby'.
```

## Numbers

Numbers returned by functions are either plain js numbers or `big.js` instances. Some functions with names ending in `Raw` may return ether.js's BigNumbers.

As input, numbers can be as plain js numbers, `big.js` instances, but also strings.

The precision used when dividing is 20 decimal places.

## Transaction Options

TODO include transaction options (see here)[https://github.com/compound-finance/compound-js#transaction-options]

## Test

Tests are available in `./test/*.test.js`. The tests are configured in `./test/index.js`. Methods are tested using a forked chain using hardhat. For free archive node access, get a provider URL from [Alchemy](http://alchemy.com/).

```
## Run all tests
npm test

## Run a single test (Mocha JS grep option)
npm test -- -g 'runs eth.getBalance'
```

## Build for Node.js & Web Browser

```
git clone ...
cd mangrove.js
npm install
npm run build
```
