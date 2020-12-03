//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

contract HasAdmin {
  address public admin;

  event SetAdmin(address value);

  constructor() {
    admin = msg.sender;
    emit SetAdmin(msg.sender);
  }

  function isAdmin(address candidate) internal view returns (bool) {
    return (candidate == admin || candidate == address(this));
  }

  function setAdmin(address _admin) public adminOnly {
    admin = _admin;
    emit SetAdmin(admin);
  }

  modifier adminOnly {
    require(isAdmin(msg.sender), "dex/adminOnly");
    _;
  }
}
