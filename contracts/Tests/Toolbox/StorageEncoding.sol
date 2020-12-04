// SPDX-License-Identifier: UNLICENSED

/* Testing bad storage encoding */

// We can't even encode storage references without the experimental encoder
pragma experimental ABIEncoderV2;

pragma solidity ^0.7.4;
import "./TestEvents.sol";
import "hardhat/console.sol";

contract StorageEncoding {}

struct S {
  uint a;
}

library Lib {
  function a(S storage s) public view {
    s; // silence warning about unused parameter
    console.log("in Lib.a: calldata received");
    console.logBytes(msg.data);
  }
}

contract StorageEncoding_Test {
  receive() external payable {}

  S sss; // We add some padding so the storage ref for s is not 0
  S ss;
  S s;

  function _test() public {
    console.log("Lib.a selector:");
    console.logBytes4(Lib.a.selector);
    console.log("___________________");

    console.log("[Encoding s manually]");
    console.log("abi.encodeWithSelector(Lib.a.selector,s)):");
    bytes memory data = abi.encodeWithSelector(Lib.a.selector, s);
    console.logBytes(data);
    console.log("Calling address(Lib).delegatecall(u)...");
    bool success;
    (success, ) = address(Lib).delegatecall(data);
    console.log("___________________");

    console.log("[Encoding s with compiler]");
    console.log("Calling Lib.a(s)...");
    Lib.a(s);
    console.log("___________________");
  }
}
