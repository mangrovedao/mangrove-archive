// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// Should be kept in sync with ../lib/test_solidity.js
// Calling test functions sends events which are interpeted by test_solidity.js
// to display results.

library TestEvents {
  event LogString(string message, uint indentLevel);

  function logString(string memory message, uint indent) internal {
    emit LogString(message, indent);
  }

  event ExpectFrom(address from);

  function expectFrom(address from) internal {
    emit ExpectFrom(from);
  }

  event TestTrue(bool success, string message);

  function check(bool success, string memory message) internal {
    emit TestTrue(success, message);
  }

  function fail(string memory message) internal {
    emit TestTrue(false, message);
  }

  function success() internal {
    emit TestTrue(true, "Success");
  }

  event TestEqUint(bool success, uint actual, uint expected, string message);
  event TestLess(bool success, uint actual, uint expected, string message);

  function min(uint a, uint b) internal pure returns (uint) {
    return a < b ? a : b;
  }

  function eq(
    uint actual,
    uint expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual == expected;
    emit TestEqUint(success, actual, expected, message);
    return success;
  }

  function less(
    uint actual,
    uint expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual < expected;
    emit TestLess(success, actual, expected, message);
    return success;
  }

  function more(
    uint actual,
    uint expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual > expected;
    emit TestLess(success, actual, expected, message);
    return success;
  }

  event TestEqString(
    bool success,
    string actual,
    string expected,
    string message
  );

  function eq(
    string memory actual,
    string memory expected,
    string memory message
  ) internal returns (bool) {
    bool success = keccak256(bytes((actual))) == keccak256(bytes((expected)));
    emit TestEqString(success, actual, expected, message);
    return success;
  }

  event TestEqAddress(
    bool success,
    address actual,
    address expected,
    string message
  );

  event TestNot0x(bool success, address addr);

  function not0x(address actual) internal returns (bool) {
    bool success = actual != address(0);
    emit TestNot0x(success, actual);
    return success;
  }

  function eq(
    address actual,
    address expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual == expected;
    emit TestEqAddress(success, actual, expected, message);
    return success;
  }

  event TestEqBytes(bool success, bytes actual, bytes expected, string message);

  function eq0(
    bytes memory actual,
    bytes memory expected,
    string memory message
  ) internal returns (bool) {
    bool success = keccak256((actual)) == keccak256((expected));
    emit TestEqBytes(success, actual, expected, message);
    return success;
  }

  event GasCost(string callname, uint value);

  function execWithCost(
    string memory callname,
    address addr,
    bytes memory data
  ) internal returns (bytes memory) {
    uint g0 = gasleft();
    (bool noRevert, bytes memory retdata) = addr.delegatecall(data);
    require(noRevert, "execWithCost should not revert");
    emit GasCost(callname, g0 - gasleft());
    return retdata;
  }
}
