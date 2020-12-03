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

  /* Usage: from a test contract t, call `expectFrom(a)` with a != t (otherwise undefined behaviour). Any subsequent non-special event emitted by t will mean "I expect a to have already emitted the exact same event". The order of expectations must be respected. 
     Formally:
     * let (e1, e2, ...) be the sequence ordering the events yielded by the transaction
     * let tests be all events emitted by the testing contract
     * let instructions be all tests interpreted by javascript
     * let froms be instructions with signature ExpectFrom(address a)
     * let regulars be all non-test events, then
     * let expects be all non-instruction tests that occur after at least one from, and for all expects e,
     * from(e) is the latest such from, and
     * match(e) is the earliest regular e' such that e' happens before e and e and e' are equal.
     The following must be true: 
     1) if match(e) is emitted by a, from(e) = ExpectFrom(a)
     2) match is a total function
     3) match is an order-preserving function
  */
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

  function succeed() internal {
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

  function revertEq(string memory actual_reason, string memory expected_reason)
    internal
    returns (bool)
  {
    return eq(actual_reason, expected_reason, "wrong revert reason");
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
