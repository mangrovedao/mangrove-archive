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

contract Failer_Test {
  receive() external payable {}

  function exec() external view {
    console.log("exec");
    require(false);
  }

  function execBig() external view {
    console.log("execBig");
    string memory wtf = new string(100_000);
    require(false, wtf);
  }

  function failed_yul_test() public {
    bytes memory b = new bytes(100_000);
    b;
    uint g0 = gasleft();
    bytes memory cd = abi.encodeWithSelector(this.execBig.selector);
    bytes memory retdata = new bytes(32);
    assembly {
      let success := delegatecall(
        500000,
        address(),
        add(cd, 32),
        4,
        add(retdata, 32),
        0
      )
    }
    console.log("GasUsed: %d", g0 - gasleft());
  }

  function failer_small_test() public {
    uint g0 = gasleft();
    (bool success, bytes memory retdata) =
      address(this).delegatecall{gas: 500_000}(
        abi.encodeWithSelector(this.exec.selector)
      );
    success;
    retdata;
    console.log("GasUsed: %d", g0 - gasleft());
  }

  function failer_big_with_retdata_bytes_test() public {
    bytes memory b = new bytes(100_000);
    b;
    uint g0 = gasleft();
    (bool success, bytes memory retdata) =
      address(this).delegatecall{gas: 500_000}(
        abi.encodeWithSelector(this.execBig.selector)
      );
    success;
    retdata;

    console.log("GasUsed: %d", g0 - gasleft());
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
