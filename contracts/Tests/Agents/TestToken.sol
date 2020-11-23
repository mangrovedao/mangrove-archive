// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "../../ERC20.sol";

contract TestToken is ERC20 {
  mapping(address => bool) admins;

  constructor(
    address _admin,
    string memory name,
    string memory symbol
  ) ERC20(name, symbol) {
    admins[_admin] = true;
  }

  function requireAdmin() internal view {
    require(admins[msg.sender], "TestToken/adminOnly");
  }

  function addAdmin(address admin) external {
    requireAdmin();
    admins[admin] = true;
  }

  function mint(address to, uint amount) external {
    requireAdmin();
    _mint(to, amount);
  }
}
