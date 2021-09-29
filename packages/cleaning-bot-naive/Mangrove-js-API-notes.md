# Adding the Mangrove.js library as a dependency

I had to turn the following TypeScript compilation flags off in order for `ts-node` to not complain about mangrove.js:

```
    //"strict": true,
    //"suppressImplicitAnyIndexErrors": true,
```

> ⚠️ Wouldn't we want these compiler options to be on in mangrove.js?

## Mangrove.js dist

I had to add `"module": "CommonJS"` in mangrove.js's `tconfig.json` to be able to use `require("../../../mangrove.js/dist/nodejs/mangrove")` from a JS file.

# Connecting to Mangrove

**OUTDATED the API was changed after this was written**
I tried to connect to a local Hardhat node started in a separate terminal with `npx hardhat node`.

```TypeScript
  const mgv = await Mangrove.connect("http://127.0.0.1:8545");
```

The error message I got confused me a bit:

```
Error: No addresses for network unknown.
```

Turns out 'unknown' at the end refers to an internal name Mangrove.js assigns to the URL i provided to `connect()`.

> ⚠️ Perhaps the error message instead could refer to the provided URL, i.e. `http://127.0.0.1:8545`?

## Addresses

I realized that I need to set up addresses for network I'm connecting to. As far as I can tell, this must happen in `constants.ts`, which is part of the Mangrove.js package.

> ⚠️ We should probably provide an API and a configuration option for providing those addresses.

> ⚠️ We should document the required and supported addresses.

The minimal addresses I had to add to `constants.ts` were:

```TypeScript
  "unknown": {
    "Mangrove": "0x5fbdb2315678afecb367f032d93f642f64180aa3",
    "MgvReader": "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9"
  }
```

**Updated 2021-09-28:** There's now automatic detection of Hardhat and a set of addresses in `mangrove-js/src/hardhatAddresses.json`. This file is written as part of the build, but also checked in to git as part of `./src` ?

The auto detection is nice, but the implementation is surprising - a more functional approach with clean separation between sources and generated artifacts would be good. Perhaps we could generate the file to a separate folder (like hardhat-deploy does) and not check it into git?

## Provider

Since mangrove.js constructs a Provider, I think it should be possible to get and use that Provider, such that it can be used for other purposes, e.g. connecting to contracts not controlled my mangrove.js.

> ⚠️ Perhaps expose `Mangrove._provider`.

# Reading the configuration

## OUTDATED the API was changed after this was written - this now works

First attempt:

```TypeScript
  const cfg = await mgv.config();
  console.dir(cfg);
```

resulted in the following error:

```
Error: network does not support ENS (operation="ENS", network="unknown", code=UNSUPPORTED_OPERATION, version=providers/5.3.0)
    at Logger.makeError (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/logger/src.ts/index.ts:213:28)
    at Logger.throwError (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/logger/src.ts/index.ts:225:20)
    at JsonRpcProvider.<anonymous> (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/providers/src.ts/base-provider.ts:1513:20)
    at step (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/providers/lib/base-provider.js:48:23)
    at Object.next (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/providers/lib/base-provider.js:29:53)
    at fulfilled (/Users/espen/dev/mangrove/mangrove.js/node_modules/@ethersproject/providers/lib/base-provider.js:20:58)
    at processTicksAndRejections (node:internal/process/task_queues:96:5) {
  reason: 'network does not support ENS',
  code: 'UNSUPPORTED_OPERATION',
  operation: 'ENS',
  network: 'unknown'
}
```

My guess it that `ethers` is trying to resolve some string. Maybe the empty string, as `config()` attempts to call `MangroveContract` with empty strings for `base` and `quote` ?

> ⚠️ Maybe the `config()` method without parameters should only read and return the global parameters?

I tried changing the implementation to do just that:

```TypeScript
    const globalConfig = await this.contract.global();
    return globalConfig;
```

but that gave me the compressed representation:

```
'0x00000000000000000000000000000000000000000000000107a1200000000000'
```

# Reading the Mangrove

## Reading Markets

I couldn't find a way to get a list of the existing markets?

> ⚠️ Maybe we should add a method for getting a list of existing markets/pairs?

# Market

**OUTDATED** I was a bit surprised that I could create a market for a non-configure/non-existant pair without error:

```TypeScript
  const market = await mgv.market({base: "Foo", quote: "Bar"});
```

The method is `async` so would expect it to actually read from the network.

> ⚠️ [Implemented] Maybe `market()` should not be `async` or it should actually give an error, if the market doesn't exist.

After adding addresses for `TokenA` and `TokenB` I can (almost) read the config of that market:

```TypeScript
  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";

  const market = await mgv.market({base: baseTokenName, quote: quoteTokenName});
  const marketConfig = await market.config();
```

**OUTDATED** I get the following cryptic error message:

```
Error: No decimals on record for token TokenA
    at Function.getDecimals (/Users/espen/dev/mangrove/mangrove.js/src/mangrove.ts:191:13)
    at Mangrove.getDecimals (/Users/espen/dev/mangrove/mangrove.js/src/mangrove.ts:109:21)
    at Mangrove.fromUnits (/Users/espen/dev/mangrove/mangrove.js/src/mangrove.ts:145:45)
    at Market.fromUnits (/Users/espen/dev/mangrove/mangrove.js/src/market.ts:105:21)
    at Market._Market_mapConfig (/Users/espen/dev/mangrove/mangrove.js/src/market.ts:47:21)
    at Market.config (/Users/espen/dev/mangrove/mangrove.js/src/market.ts:69:28)
    at processTicksAndRejections (node:internal/process/task_queues:96:5)
    at async main (/Users/espen/dev/mangrove/packages/cleaning-bot-naive/src/cleaning-bot-naive.ts:20:24)
```

Turns out I need to call `cacheDecimals()` for each of the tokens.

> ⚠️ [Implemented] Could Mangrove.js call `cacheDecimals()` automatically when needed?

**OUTDATED The API was changed** However, the structure has some obscure contents:

```Javascript
[
  false,
  BigNumber { _hex: '0x00', _isBigNumber: true },
  BigNumber { _hex: '0x00', _isBigNumber: true },
  BigNumber { _hex: '0x00', _isBigNumber: true },
  BigNumber { _hex: '0x00', _isBigNumber: true },
  false,
  BigNumber { _hex: '0x00', _isBigNumber: true },
  BigNumber { _hex: '0x00', _isBigNumber: true },
  active: false,
  fee: BigNumber { _hex: '0x00', _isBigNumber: true },
  density: BigNumber { _hex: '0x00', _isBigNumber: true },
  overhead_gasbase: BigNumber { _hex: '0x00', _isBigNumber: true },
  offer_gasbase: BigNumber { _hex: '0x00', _isBigNumber: true },
  lock: false,
  best: BigNumber { _hex: '0x00', _isBigNumber: true },
  last: BigNumber { _hex: '0x00', _isBigNumber: true }
]
```

> ⚠️ [Implemented] Could we give all elements in the config meaningful names?

## Activating markets

The cleaning bot should obviously not activate markets, but it requires an active market to operate on. So I'm adding some temporary code to do just that.

I couldn't find any API for activating markets?

> ⚠️ [Resolved: Not supported for now] Should Mangrove.js have API's for the administrative stuff, like activating markets?

## Contract API

For the auto-generated API (via typechain), currently mappings that gives rise to Market.contract.offers() (in generated Mangrove.d.ts) get unhelpful parameter names:

```TypeScript
    offers(
      arg0: string,
      arg1: string,
      arg2: BigNumberish,
      overrides?: CallOverrides
    ): Promise<[string]>;
```

Since this stems from Solidity and goes through an auto-generation phase to generate the TypeScript bindings, I understand there may be other considerations here. But in a public API it would be very nice to have all method by fairly self-documenting.

## Subscribing

The `subscribe()` method is undocumented. The callback takes `any` as an argument, so I don't know what to expect?

> ⚠️ Some documentation on how to use `subscribe()` and its options would be good.

It seems one has to filter the feed oneself.

> ⚠️ An option for only subscribing to certain updates (e.g. `OfferWrite` on `asks`) would be nice.

## Cached order book

I'd like to maintain a cached copy of the order book, so I don't have to read the full order book via MgvReader all the time. It seems that mangrove.js maintains such a cache (`semibook`) - could we expose that to the subscribed listeners?

> ⚠️ Exposing the cached order book would be a nice service.
