// Run solidity tests for contracts in argTestContractNames.
// If showTestEvents is true, all events from the testing contract logged during test run will be shown.
// If showEvents is true, all events NOT from the testing contract logged during test run will be shown.
// Note that Buidler's console runs parallel to events and will be shown regardless
// (and the console messages are not reverted like regular logs).
module.exports = (
  {argTestContractNames, showEvents, showTestEvents, prefix: prefixString},
  hre /* Buidler env */
) => {
  const util = require("util");
  const debug = require("debug")("hardhat:test-solidity");
  const ethers = hre.ethers; // Local ethers.js shortcut
  const deploy = hre.deploy;
  const Mocha = require("mocha"); // Testing library
  const mocha = new Mocha(); // Instantiate to generate tests
  const assert = require("chai").assert; // Assertion library

  /* Remember address => name mapping received by events */
  const registers = {};
  const normalizeReg = (addr) => `${addr}`.toLowerCase();
  const getRegister = (addr) => {
    const name = registers[normalizeReg(addr)];
    debug(`resolved ${addr} to ${name}`);
    return name;
  };
  const setRegister = (addr, name) => (registers[normalizeReg(addr)] = name);

  // Iterate through known contracts and try to parse the raw log given
  const tryParseLog = (artifacts, rawLog) => {
    let log;
    let originator;
    for (const artifact of artifacts) {
      const interface = new ethers.utils.Interface(artifact.abi);
      try {
        log = interface.parseLog(rawLog);
        originator = artifact;
        break;
      } catch (e) {
        continue;
      }
    }
    return {log, originator};
  };

  const tryDisplayLog = (log, rawLog, originator) => {
    if (!log) {
      console.log("Could not parse the following raw log:");
      console.dir(rawLog);
    } else {
      console.log(`Event ${log.signature}`);
      let address = getRegister(rawLog.address) || rawLog.address;
      console.log(` issued by ${originator.contractName}/${address}`);
      //console.dir(rawLog,{depth:null});
      const normalized = log.eventFragment.inputs.map((input, i) => {
        let nameOrPos = input.name || i;
        let value;
        if (input.type === "address") {
          value = getRegister(log.args[nameOrPos]) || log.args[nameOrPos];
        } else if (input.type.startsWith("uint")) {
          value = formatArg(log.args[nameOrPos]);
        } else {
          value = log.args[nameOrPos];
        }

        return {nameOrPos, value, type: input.type};
      });
      let padLength = Math.max(
        ...normalized.map((input) => `${input.nameOrPos}`.length)
      );
      for (const input of normalized) {
        console.log(
          `  ${`${input.nameOrPos}`.padEnd(padLength, " ")}: ${input.value} (${
            input.type
          })`
        );
      }
      console.log("");
    }
  };

  const genericFail = ({success, actual, expected, message}) => {
    if (!success) {
      assert.fail(
        `${message}\nExpected: ${formatArg(expected)}\nActual:   ${formatArg(
          actual
        )}`
      );
    }
  };

  // Testing schema, must be kept in sync with contracts/Test.sol
  const schema = {
    testContract: "_Test", // naming convention for testing contracts
    preContract: "_Pre", // naming convention for pre*-testing contracts
    isTestContract(name) {
      return name.endsWith("_Test");
    },
    toTest(contractName) {
      return `${contractName}_Test`;
    },
    toPre(contractName) {
      return `${contractName}_Pre`;
    },
    // Functions of testing contracts that follow these conventions will
    // be run by the testing routine below.
    isTestFunction(fn) {
      return fn.endsWith("_test()");
    },
    isTestFailFunction(fn) {
      return fn.endsWith("_testFail()");
    },
    isBeforeAllFunction(fn) {
      return fn.endsWith("_beforeAll()");
    },
    // Tests are events emitted by the test functions
    // see contracts/Test.sol for the event definitions.
    // The object below says how to interpret those events.
    // They are interpreted even if showEvents if false.
    events: {
      TestEqAddress: {trigger: genericFail},
      TestEqString: {trigger: genericFail},
      TestEqUint: {trigger: genericFail},
      TestEqBytes: {trigger: genericFail},
      TestLess: {
        trigger: ({success, message, actual, expected}) => {
          if (!success) {
            assert.fail(`${actual} should be < ${expected} (${message})`);
          }
        },
      },
      TestMore: {
        trigger: ({success, message, actual, expected}) => {
          if (!success) {
            assert.fail(`${actual} should be > ${expected} (${message})`);
          }
        },
      },
      TestTrue: {
        trigger: ({message, success}) => {
          if (!success) assert.fail(message);
        },
      },
    },
  };

  // Test arguments are formatted for readability.
  // In particular, the following heuristic is used for numbers:
  // - show the raw number below 1 billion
  // - show in units of 1 billion (that is, 1 gwei) if below 10^6 gwei
  // - otherwise, show in units of 10^18 (that is, 1 ether)
  const formatArg = (arg) => {
    if (ethers.BigNumber.isBigNumber(arg)) {
      if (arg.lt(ethers.BigNumber.from(10 ** 9))) {
        return arg.toString();
      } else if (arg.lt(ethers.utils.parseUnits("1000000", "gwei"))) {
        return `${ethers.utils.formatUnits(arg, "gwei")} gwei`;
      } else {
        return `${ethers.utils.formatUnits(arg, "ether")} ether`;
      }
    } else {
      return arg.toString();
    }
  };

  // Recursively deploy libraries associated to a contract, with caching.
  const deployLibraries = (() => {
    const deployedLibraries = {};
    const deploy = async (contractName) => {
      const accounts = await ethers.getSigners();
      const artifact = await hre.artifacts.readArtifact(contractName);
      let returnLibraries = {};
      for (const file in artifact.linkReferences) {
        for (const libName in artifact.linkReferences[file]) {
          if (!deployedLibraries[libName]) {
            const libraries = await deployLibraries(libName);
            const deployFrom = await accounts[0].getAddress();
            const opts = {from: deployFrom, libraries};
            debug("deploying lib %s %o", libName, opts);
            const lib = await hre.deployments.deploy(libName, opts);
            deployedLibraries[libName] = lib;
          }
          returnLibraries[libName] = deployedLibraries[libName].address;
        }
      }
      return returnLibraries;
    };
    return deploy;
  })();

  // Recursive function looks through known contracts and deploys
  // as much as necessary. For instance, if given "C_Test",
  // and "C_Test_Pre" and "C_Test_Pre_Pre" exist, will deploy:
  // - C_Test_Pre_Pre (at some address <a1>)
  // - C_Test_Pre with constructor argument <a1> (at some address <a2>)
  // - C_Test with constructor argument <a2>
  const deployWithPres = async (artifacts, currentName) => {
    const nextName = schema.toPre(currentName);
    let args = [];
    if (artifacts.some((c) => c.contractName == nextName)) {
      const next = await deployWithPres(artifacts, nextName);
      args = [next.address];
    }
    const libraries = await deployLibraries(currentName);
    const accounts = await ethers.getSigners();
    const deployFrom = await accounts[0].getAddress();
    const opts = {from: deployFrom, args, libraries};
    debug("deployWithPres ends recursion with %s %o", currentName, opts);
    const deployed = await hre.deployments.deploy(currentName, opts);
    const contract = new ethers.Contract(
      deployed.address,
      deployed.abi,
      accounts[0]
    );
    return contract;
  };
  // Iterate through contracts that need testing. For each:
  // - Fund the test contract with 1000 ethers
  // - Run any functions that end with _beforeAll
  // - Run each test function
  // TODO: reset to initial snapshot after each test function
  const createTests = async (artifacts, testContracts) => {
    for (const testContractObj of testContracts) {
      const suite = new Mocha.Suite(testContractObj.contractName, {});
      mocha.suite.addSuite(suite);
      suite.timeout(30000);

      const testContract = await deployWithPres(
        artifacts,
        testContractObj.contractName
      );

      const processLogs = (receipt) => {
        let expectations = {
          currentAddress: null,
          list: [],
        };

        for (const rawLog of receipt.logs) {
          //console.dir(expectations,{depth:null});
          const {log, originator} = tryParseLog(artifacts, rawLog);
          if (rawLog.address === testContract.address) {
            if (showTestEvents) {
              tryDisplayLog(log, rawLog, originator);
            }
            // do we recognise the event
            if (log && schema.events[log.name]) {
              schema.events[log.name].trigger(log.args);
            } else if (log && log.name == "ExpectFrom") {
              //console.dir(log);
              expectations.currentAddress = log.args.from;
              //schema.expectEvents[log.name].trigger(expectations,log.args);
            } else if (log && log.name == "Register") {
              //console.log("registering %o",log.args);
              setRegister(log.args.addr, log.args.name);
            } else if (expectations.currentAddress) {
              // Maybe we're emitting something to be expected

              const trimmedLog = Object.assign({}, log);
              delete trimmedLog.eventFragment;

              expectations.list.push({
                address: expectations.currentAddress,
                raw: {topics: rawLog.topics, data: rawLog.data},
                parsed: trimmedLog,
              });
            }
          } else {
            if (showEvents) {
              tryDisplayLog(log, rawLog, originator);
            }

            if (expectations.list.length > 0) {
              const head = expectations.list[0];
              if (
                rawLog.address === head.address &&
                rawLog.topics.every((t, i) => head.raw.topics[i] === t) &&
                rawLog.data === head.raw.data
              ) {
                expectations.list.shift();
              }
            }
          }
        }

        if (expectations.list.length > 0) {
          const err = [
            "Missing some expected events, use --show-events to see all events received.",
            "Missed events:",
            util.inspect(expectations.list, {depth: null}),
          ];

          assert.fail(err.join("\n"));
        }
      };

      let suiteSnapnum;

      // Run _beforeAll functions
      suite.beforeAll(
        `Before testing, snapshot & fund ${testContractObj.contractName}`,
        async function () {
          // Rember before state
          suiteSnapnum = await hre.network.provider.request({
            method: "evm_snapshot",
          });
          // Fund test contract
          const accounts = await ethers.getSigners();
          await accounts[0].sendTransaction({
            to: testContract.address,
            value: ethers.utils.parseUnits("1000", "ether"),
          });
        }
      );

      suite.afterAll(`After testing, revert to former state`, async () => {
        await hre.network.provider.request({
          method: "evm_revert",
          params: [suiteSnapnum],
        });
      });

      sortedFunctions = Object.entries(
        testContract.interface.functions
      ).sort(([fnA], [fnB]) => fnA.localeCompare(fnB, "en", {}));

      for (const [fnName, fnFragment] of sortedFunctions) {
        if (
          schema.isBeforeAllFunction(fnName) &&
          fnFragment.inputs.length == 0
        ) {
          suite.beforeAll(
            `${testContractObj.contractName}.${fnName}`,
            async () => {
              debug("Running beforeAll named %s", fnName);
              let receipt = await (await testContract[fnName]()).wait();
              processLogs(receipt);
            }
          );
        }
      }

      // Run each _test function
      const regexp = new RegExp(`^${prefixString}.*`);
      for (const [fnName, fnFragment] of sortedFunctions) {
        debug("Creating test for %s", fnName);
        if (schema.isTestFailFunction(fnName)) {
          // TODO or remove testFail
        } else if (schema.isTestFunction(fnName)) {
          if (!regexp.test(fnName)) {
            continue;
          }
          const test = new Mocha.Test(
            `${testContractObj.contractName}.${fnName}`,
            async () => {
              const snapnum = await hre.network.provider.request({
                method: "evm_snapshot",
              });
              // Once a _test function has been call, inspect logs to check
              // for failed tests. Failed tests/logs after the first one are not
              // shown.
              let receipt = await (await testContract[fnName]()).wait();
              processLogs(receipt);
              await hre.network.provider.request({
                method: "evm_revert",
                params: [snapnum],
              });
            }
          );

          suite.addTest(test);
        }
      }
    }
  };

  return new Promise(async (resolve, reject) => {
    try {
      // Make sure contracts are freshly compiled before running tests
      await hre.run("compile");
      // Get the list of contracts as parsed by Buidler
      const getArtifacts = async () => {
        return Promise.all(
          (await hre.artifacts.getAllFullyQualifiedNames()).map(
            async (n) => await hre.artifacts.readArtifact(n)
          )
        );
      };
      const artifacts = await getArtifacts();

      // Find all contracts C such that C_Test exists.
      const testableContracts = artifacts.filter((c) => {
        return schema.isTestContract(c.contractName);
      });

      // If no specific contract has been given, try to test all contracts
      const testContracts =
        argTestContractNames.length == 0
          ? testableContracts
          : artifacts.filter((c) =>
              argTestContractNames.map(schema.toTest).includes(c.contractName)
            );

      debug(
        "Artifacts names: %o",
        artifacts.map((c) => c.contractName)
      );
      debug(
        "Testable contracts: %o",
        testableContracts.map((c) => c.contractName)
      );
      debug("Contracts given: %o", argTestContractNames);
      debug(
        "Will run tests of: %o",
        testContracts.map((c) => c.contractName)
      );
      await createTests(artifacts, testContracts);
      mocha.run((failures) => {
        if (failures) {
          reject("At least one test failed.");
        } else {
          resolve("All tests passed.");
        }
      });
    } catch (e) {
      reject(e);
    }
  });
};
