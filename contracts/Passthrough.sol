// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

/* 
  Experimental contract to simulate an EOA which can call arbitrary functions.
  How to use :
  
  p = new Passthrough();
  p.calls(<address>,Contract.function.selector,arg1,...argN);
*/

contract Passthrough {
  function calls(
    address addr,
    bytes4 signature,
    uint256 arg1
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1));
  }

  function calls(
    address addr,
    bytes4 signature,
    uint256 arg1,
    uint256 arg2
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1, arg2));
  }

  function calls(
    address addr,
    bytes4 signature,
    uint256 arg1,
    uint256 arg2,
    uint256 arg3
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1, arg2, arg3));
  }

  function calls(
    address addr,
    bytes4 signature,
    uint256 arg1,
    uint256 arg2,
    uint256 arg3,
    uint256 arg4
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1, arg2, arg3, arg4));
  }

  function calls(
    address addr,
    bytes4 signature,
    address arg1
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1));
  }

  function calls(
    address addr,
    bytes4 signature,
    string memory arg1
  ) public returns (bool, bytes memory) {
    return addr.call(abi.encodeWithSelector(signature, arg1));
  }
}
