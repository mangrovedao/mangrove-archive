// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "../../ERC20.sol";

contract TestToken is ERC20 {
  address admin;

  constructor(
    address _admin,
    string memory name,
    string memory symbol
  ) ERC20(name, symbol) {
    admin = _admin;
  }

  function mint(address to, uint amount) external {
    require(msg.sender == admin, "non-admin minting");
    _mint(to, amount);
  }
}
