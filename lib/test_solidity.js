// Run solidity tests for contracts in argTestContractNames.
// If showEvents is true, all events logged during test run will be shown.
// Note that Buidler's console runs parallel to events and will be shown regardless
// (and the console messages are not reverted like regular logs).
module.exports = (
  {argTestContractNames, showEvents},
  bre /* Buidler env */
) => {
  const ethers = bre.ethers; // Local ethers.js shortcut
  const Mocha = require("mocha"); // Testing library
  const mocha = new Mocha(); // Instantiate to generate tests
  const assert = require("chai").assert; // Assertion library

  // Get the list of contracts as parsed by Buidler
  const contractNames = (() => {
    const fs = require("fs");
    const path = require("path");
    return fs
      .readdirSync(bre.config.paths.artifacts)
      .map((file) => {
        if (file.endsWith(".json")) {
          const filepath = path.resolve(bre.config.paths.artifacts, file);
          const jsondata = JSON.parse(fs.readFileSync(filepath, "utf8"));
          return jsondata.contractName;
        } else {
          return undefined;
        }
      })
      .filter((k) => !!k);
  })();

  // Iterate through known contracts and try to parse the raw log given
  const tryDisplayLog = async (rawLog) => {
    let parsed = false;
    for (const contractName of contractNames) {
      const Contract = await ethers.getContractFactory(contractName);
      let log;
      try {
        log = Contract.interface.parseLog(rawLog);
      } catch (e) {
        continue;
      }
      console.log(`Event ${log.signature} (in ${contractName})`);
      let typeLengths = log.eventFragment.inputs.map(
        (type) => type.name.length
      );
      let padLength = Math.max(...typeLengths);
      for (const type of log.eventFragment.inputs) {
        console.log(
          `  ${type.name.padEnd(padLength, " ")}: ${log.args[type.name]} (${
            type.type
          })`
        );
      }
      console.log("");
      parsed = true;
      break;
    }
    if (!parsed) {
      console.log("Could not parse the following raw log:");
      console.dir(rawLog);
    }
  };

  // Testing schema, must be kept in sync with contracts/Test.sol
  const schema = {
    testContract: "_Test", // naming convention for testing contracts
    preContract: "_Pre", // naming convention for pre*-testing contracts
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
      TestEqAddress: {
        fail: ({actual, expected, message}) => {
          assert.fail(
            `${message}\nExpected: ${formatArg(
              expected
            )}\nActual:   ${formatArg(actual)}`
          );
        },
      },
      TestEqString: {
        fail: ({actual, expected, message}) => {
          assert.fail(
            `${message}\nExpected: ${formatArg(
              expected
            )}\nActual:   ${formatArg(actual)}`
          );
        },
      },
      TestEqUint: {
        fail: ({actual, expected, message}) => {
          assert.fail(
            `${message}\nExpected: ${formatArg(
              expected
            )}\nActual:   ${formatArg(actual)}`
          );
        },
      },
      TestTrue: {
        fail: ({message}) => {
          assert.fail(message);
        },
      },
      TestEqBytes: {
        fail: ({actual, expected, message}) => {
          assert.fail(
            `${message}\nExpected: ${formatArg(
              expected
            )}\nActual:   ${formatArg(actual)}`
          );
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

  // Recursive function looks through known contracts and deploys
  // as much as necessary. For instance, if given "C_Test",
  // and "C_Test_Pre" and "C_Test_Pre_Pre" exist, will deploy:
  // - C_Test_Pre_Pre (at some address <a1>)
  // - C_Test_Pre with constructor argument <a1> (at some address <a2>)
  // - C_Test with constructor argument <a2>
  const deployWithPres = async (currentName) => {
    const Current = await ethers.getContractFactory(currentName);
    const nextName = schema.toPre(currentName);
    if (contractNames.includes(nextName)) {
      const next = await deployWithPres(nextName);
      return await Current.deploy(next.address);
    } else {
      return await Current.deploy();
    }
  };

  // Find all contracts C such that C_Test exists.
  const testableContractNames = contractNames.filter((c) =>
    contractNames.includes(schema.toTest(c))
  );

  // Begin setting up tests here

  // If specific contracts have been given, throw an error if they are not
  // testable
  for (const contractName of argTestContractNames) {
    if (!testableContractNames.includes(contractName)) {
      throw new Error(
        `Could not find contract ${contractName} among testable contracts`
      );
    }
  }

  // If no specific contract has been given, try to test all contracts
  const testContractNames =
    argTestContractNames.length == 0
      ? testableContractNames
      : argTestContractNames;

  // Iterate through contracts that need testing. For each:
  // - Fund the test contract with 1000 ethers
  // - Run any functions that end with _beforeAll
  // - Run each test function
  // TODO: reset to initial snapshot after each test function
  const createTests = async () => {
    const TestingContract = await ethers.getContractFactory("Test");
    for (const contractName of testContractNames) {
      const suite = new Mocha.Suite(contractName, {});
      mocha.suite.addSuite(suite);

      const testContract = await deployWithPres(schema.toTest(contractName));

      suite.beforeAll(`Before testing ${contractName}`, async function () {
        // Fund test contract
        const accounts = await ethers.getSigners();
        await accounts[0].sendTransaction({
          to: testContract.address,
          value: ethers.utils.parseUnits("1000", "ether"),
        });

        // Run _beforeAll functions
        for (const fn in testContract.interface.functions) {
          if (
            schema.isBeforeAllFunction(fn) &&
            testContract.interface.functions[fn].inputs.length == 0
          ) {
            await testContract[fn]();
          }
        }
      });

      // Run each _test function
      for (const fn in testContract.interface.functions) {
        if (schema.isTestFailFunction(fn)) {
          // TODO or remove testFail
        } else if (schema.isTestFunction(fn)) {
          const test = new Mocha.Test(fn, async () => {
            // Once a _test function has been call, inspect logs to check
            // for failed tests. Failed tests/logs after the first one are not
            // shown.
            let receipt = await (await testContract[fn]()).wait();
            for (const rawLog of receipt.logs) {
              let log;
              try {
                log = TestingContract.interface.parseLog(rawLog);
              } catch (e) {}
              if (log) {
                if (!log.args.success) {
                  schema.events[log.name].fail(log.args);
                } // Successful tests are silent
              } else {
                // Logs are also used to display regular events
                if (showEvents) {
                  // Regular event, try to parse it
                  await tryDisplayLog(rawLog);
                }
              }
            }
          });

          suite.addTest(test);
        }
      }
    }
  };

  return new Promise(async (resolve, reject) => {
    try {
      // Make sure contracts are freshly compiled before running tests
      await bre.run("compile");
      await createTests();
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
