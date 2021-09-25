import * as shell from "shelljs";

const distAbiDir = "dist/nodejs/";
shell.mkdir("-p", distAbiDir);
shell.cp(
  "-R",
  "node_modules/@giry/mangrove-solidity/dist/mangrove-abis",
  "dist/nodejs/"
);
