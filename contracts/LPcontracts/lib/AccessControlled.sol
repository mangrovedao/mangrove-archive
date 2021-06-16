pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

contract AccessControlled {
  address admin;

  constructor() {
    admin = msg.sender;
  }

  modifier onlyCaller(address caller) {
    require(msg.sender == caller, "AccessControlled/Invalid");
    _;
  }

  modifier onlyAdmin(){
    require(msg.sender == admin, "AccessControlled/Invalid");
    _;
  }
    
  function setAdmin(address _admin) external onlyAdmin {
    admin = _admin;
  }
}