// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "../../ERC20BL.sol";

contract TestToken is ERC20BL {
  mapping(address => bool) admins;

  constructor(
    address admin,
    string memory name,
    string memory symbol
  ) ERC20BL(name, symbol) {
    admins[admin] = true;
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

  function burn(address account, uint amount) external {
    requireAdmin();
    _burn(account, amount);
  }

  function blacklists(address account) external {
    requireAdmin();
    _blacklists(account);
  }

  function whitelists(address account) external {
    requireAdmin();
    _whitelists(account);
  }
}
