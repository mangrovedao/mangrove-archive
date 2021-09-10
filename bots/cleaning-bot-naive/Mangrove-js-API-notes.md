# Connecting to Mangrove
I tried to connect to a local Hardhat node started in a separate terminal with `npx hardhat node`.

```TypeScript
  const mgv = await Mangrove.connect("http://127.0.0.1:8545");
```

The error message I got confused me a bit:

```
Error: No addresses for network unknown.
```

Turns out 'unknown' at the end refers to an internal name Mangrove.js assigns to the URL i provided to `connect()`. Perhaps the error message instead could refer to the provided URL, i.e. `http://127.0.0.1:8545`?


## Addresses
I realized that I need to set up addresses for network I'm connecting to. As far as I can tell, this must happen in `constants.ts`. However, this is part of the Mangrove.js package, so we should probably provide an API and a configuration option for providing those addresses.

The minimal addresses I had to add to `constants.ts` were:

```TypeScript
  "unknown": {
    "Mangrove": "0x5fbdb2315678afecb367f032d93f642f64180aa3",
    "MgvReader": "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9"
  }
```
