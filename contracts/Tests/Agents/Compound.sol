// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../interfaces.sol";
import "hardhat/console.sol";

import "../Toolbox/TestUtils.sol";
import "../Toolbox/Display.sol";

import "./TestToken.sol";

contract Compound {
  constructor() {}

  mapping(ERC20 => mapping(address => uint)) deposits;
  mapping(ERC20 => TestToken) cTokens;

  //function grant(address to, IERC20 token, uint amount) {
  //deposits[token][to] += amount;
  //c(token).mint(to, amount);
  //}

  function c(ERC20 token) public returns (TestToken) {
    if (address(cTokens[token]) == address(0)) {
      string memory cName = Display.append("c", token.name());
      string memory cSymbol = Display.append("c", token.symbol());
      cTokens[token] = new TestToken(address(this), cName, cSymbol);
    }

    return cTokens[token];
  }

  function mint(ERC20 token, uint amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    deposits[token][msg.sender] += amount;
    c(token).mint(msg.sender, amount);
  }

  function redeem(
    address to,
    ERC20 token,
    uint amount
  ) external {
    c(token).burn(msg.sender, amount);
    token.transfer(to, amount);
  }
}
