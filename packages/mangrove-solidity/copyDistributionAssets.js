const shell = require("shelljs");

const distAbiDir = process.cwd() + "/dist/mangrove-abis/";
shell.mkdir("-p", distAbiDir);
shell.cd("build/exported-abis/cache/solpp-generated-contracts/"); // Workaround because shelljs.cp replicates the path to the files (contrary to regular `cp -R`)
shell.cp("-R", "./*", distAbiDir);
