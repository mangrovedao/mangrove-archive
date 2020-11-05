// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "hardhat/console.sol";

contract Greeter {
  string greeting;

  constructor(string memory _greeting) {
    greeting = _greeting;
  }

  function greet() public view returns (string memory) {
    console.log("logging greeting: %s", greeting);
    return greeting;
  }
}

import "./Test.sol";

contract Greeter_Test {
  string a;

  Greeter g;

  constructor() {
    g = new Greeter("HOY");
  }

  function greeting_test() public {
    string memory res = g.greet();
    Test.testEq("HOY", res, "greeting not as expected");
  }

  function failing_test() public {
    Test.testEq(1, 1, "uint test fail");
    Test.testEq("a", "a", "string test fail");
    Test.testEq0(bytes("bla"), bytes("bli"), "bytes test fail");
    Test.testEq(address(this), address(0x0), "address test fail");
    Test.testTrue(true, "bool test true fail");
    Test.testTrue(false, "bool test false fail");
  }

  function deep_failing_test() public view {
    console.log("in deep_failing_test");
    bad();
  }

  function bad() public view {
    console.log("in bad");
    bad2();
  }

  function bad2() public view {
    this.bad3();
  }

  function bad3() public pure {
    require(false, "bad3 failure");
  }
}
