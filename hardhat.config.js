//usePlugin("@nomiclabs/buidler-truffle5");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("adhusson-hardhat-solpp");
const test_solidity = require("./lib/test_solidity.js");

// Special task for running Solidity tests
task(
  "test-solidity",
  "[Giry] Run tests of Solidity contracts with suffix _Test"
)
  .addFlag("showEvents", "Show all non-test events during tests")
  .addFlag("showTestEvents", "Show all test events during tests")
  .addFlag(
    "showTx",
    "Show all transaction hashes (disables revert between tests)"
  )
  .addFlag("showGas", "Show gas used for each test")
  .addFlag(
    "details",
    "Log events interpreted by the logFormatters hardhat.config parameter for additional details on the tests"
  )
  .addOptionalParam(
    "prefix",
    "Match test function names for prefix. Javascript regex. Remember to escape backslash and surround with single quotes if necessary.",
    ".*",
    types.string
  )
  .addOptionalVariadicPositionalParam(
    "contracts",
    "Which contracts to test (default:all)"
  )
  .setAction(async (params, hre) => {
    await test_solidity(
      {
        argTestContractNames: params.contracts || [],
        details: params.details,
        showGas: params.showGas,
        showEvents: params.showEvents,
        showTestEvents: params.showTestEvents,
        prefix: params.prefix,
      },
      hre
    );
  });

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      blockGasLimit: 7000000000,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  solidity: {
    version: "0.7.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200000000,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./build",
  },
  solpp: {
    includes: ["./solpp_config"],
  },
  logFormatters: {
    Success: (log, rawLog, originator, formatArg) => {
      console.log(`┏ Offer ${formatArg(log.args.offerId)} consumed`);
      console.log(`┃ takerWants ${formatArg(log.args.takerWants)}`);
      console.log(`┗ takerGives ${formatArg(log.args.takerGives)}`);
      console.log(" ");
    },
    ERC20Balances: (log, rawLog, originator, formatArg) => {
      /* Reminder:

      event ERC20Balances(
      address[] tokens,
      address[] accounts,
      uint[] balances,
    );

      */

      const tokens = {};

      log.args.tokens.forEach((token, i) => {
        tokens[token] = [];
      });

      log.args.tokens.forEach((token, i) => {
        const pad = i * log.args.accounts.length;
        log.args.accounts.forEach((account, j) => {
          if (!tokens[token]) tokens[token] = [];
          tokens[token].push({
            account: formatArg(account, "address"),
            balance: formatArg(log.args.balances[pad + j]),
          });
        });
      });

      const lineA = ({ account, balance }) => {
        const p = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padEnd(n);
        const ps = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padStart(n);
        return ` ${ps(account, 15)} │ ${p(balance, 10)}`;
      };

      Object.entries(tokens).forEach(([token, balances]) => {
        console.log(formatArg(token, "address").padStart(19));
        console.log("─".repeat(17) + "┬" + "─".repeat(14));
        balances.forEach((info) => {
          console.log(lineA(info));
        });
      });
    },
    OBState: (log, rawLog, originator, formatArg) => {
      /* Reminder:

      event OBState(
      uint[] offerIds,
      uint[] wants,
      uint[] gives,
      address[] makerAddr
    );

      */

      const ob = log.args.offerIds.map((id, i) => {
        return {
          id: formatArg(id),
          wants: formatArg(log.args.wants[i]),
          gives: formatArg(log.args.gives[i]),
          maker: formatArg(log.args.makerAddr[i], "address"),
          gas: formatArg(log.args.gasreqs[i]),
        };
      });

      const lineA = ({ id, wants, gives, maker, gas }) => {
        const p = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padEnd(n);
        return ` ${p(id, 3)}: ${p(wants, 15)}${p(gives, 15)}${p(gas, 15)}${p(
          maker,
          15
        )}`;
      };
      //const lineB = ({gas,gasprice});

      console.log(
        " " +
          lineA({
            id: "id",
            wants: "wants",
            gives: "gives",
            gas: "gasreq",
            maker: "maker",
          })
      );
      lineLength = 1 + 3 + 2 + 15 + 15 + 15 + 15;
      console.log("├" + "─".repeat(lineLength - 1) + "┤");
      ob.forEach((o) => console.log(lineA(o)));
      console.log("└" + "─".repeat(lineLength - 1) + "┘");
    },
    LogString: (log) => {
      console.log(" ".repeat(log.args.indentLevel) + log.args.message);
    },
  },
};
