// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// Base Test contract. Test contracts should extend it.
// Should be kept in sync with ../lib/test_solidity.js
// Calling test functions sends events which are interpeted by test_solidity.js
// to display results.
contract Test {
  receive() external payable {}

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

  event TestEqUint(
    bool success,
    uint256 actual,
    uint256 expected,
    string message
  );

  function testEq(
    uint256 actual,
    uint256 expected,
    string memory message
  ) internal {
    bool success = actual == expected;
    emit TestEqUint(success, actual, expected, message);
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
  ) internal {
    bool success = keccak256(bytes((actual))) == keccak256(bytes((expected)));
    emit TestEqString(success, actual, expected, message);
  }

  event TestEqAddress(
    bool success,
    address actual,
    address expected,
    string message
  );

  function testEq(
    address actual,
    address expected,
    string memory message
  ) internal {
    bool success = actual == expected;
    emit TestEqAddress(success, actual, expected, message);
  }

  event TestEqBytes(bool success, bytes actual, bytes expected, string message);

  function testEq0(
    bytes memory actual,
    bytes memory expected,
    string memory message
  ) internal {
    bool success = keccak256((actual)) == keccak256((expected));
    emit TestEqBytes(success, actual, expected, message);
  }
}
