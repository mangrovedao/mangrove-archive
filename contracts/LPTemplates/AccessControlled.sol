pragma solidity ^0.7.0;
pragma abicoder v2;

contract AccessControlled {
  address admin;

  constructor() {
    admin = msg.sender;
  }

  modifier onlyCaller(address caller) {
    require(msg.sender == caller, "AccessControlled/Invalid");
    _;
  }

  function setAdmin(address _admin) external onlyCaller(admin) {
    admin = _admin;
  }
}
