// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// Base Test contract. Test contracts should extend it.
// Should be kept in sync with ../lib/test_solidity.js
// Calling test functions sends events which are interpeted by test_solidity.js
// to display results.
library Test {
  event ExpectFrom(address from);

  function expectFrom(address from) internal {
    emit ExpectFrom(from);
  }

  event TestTrue(bool success, string message);

  function testTrue(bool success, string memory message) internal {
    emit TestTrue(success, message);
  }

  function testFail(string memory message) internal {
    emit TestTrue(false, message);
  }

  function testSuccess() internal {
    emit TestTrue(true, "Success");
  }

  event TestEqUint(bool success, uint actual, uint expected, string message);

  function min(uint a, uint b) internal pure returns (uint) {
    return a < b ? a : b;
  }

  function testEq(
    uint actual,
    uint expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual == expected;
    emit TestEqUint(success, actual, expected, message);
    return success;
  }

  event TestEqString(
    bool success,
    string actual,
    string expected,
    string message
  );

  function testEq(
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

  function testNot0x(address actual) internal returns (bool) {
    bool success = actual != address(0);
    emit TestNot0x(success, actual);
    return success;
  }

  function testEq(
    address actual,
    address expected,
    string memory message
  ) internal returns (bool) {
    bool success = actual == expected;
    emit TestEqAddress(success, actual, expected, message);
    return success;
  }

  event TestEqBytes(bool success, bytes actual, bytes expected, string message);

  function testEq0(
    bytes memory actual,
    bytes memory expected,
    string memory message
  ) internal returns (bool) {
    bool success = keccak256((actual)) == keccak256((expected));
    emit TestEqBytes(success, actual, expected, message);
    return success;
  }
}
