// SPDX-License-Identifier: UNLICENSED

// We can't even encode storage references without the experimental encoder
pragma experimental ABIEncoderV2;

pragma solidity ^0.7.4;
import "./TestEvents.sol";
import "hardhat/console.sol";

contract Throw_Test {
  receive() external payable {}

  function throws() external {
    require(false, "I threw up for some reason");
  }

  function not_enough_gas_to_call_test() public {
    try this.throws{gas: 100}() {
      console.log("Succeeded");
    } catch Error(string memory revert_reason) {
      console.log(revert_reason);
    }
  }
}
