// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

interface ERC20 {
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  function approve(address _spender, uint256 _value)
    external
    returns (bool success);
}

interface Dex {
  function REQ_TOKEN() external returns (address);

  function OFR_TOKEN() external returns (address);
}

contract Maker {
  address immutable REQ_TOKEN;
  address immutable OFR_TOKEN;
  address immutable DEX; // Address of a (REQ_TOKEN,OFR_TOKEN) DEX
  address private immutable THIS;

  constructor(
    address reqToken,
    address ofrToken,
    address dex2
  ) {
    REQ_TOKEN = reqToken;
    OFR_TOKEN = ofrToken;
    DEX = dex2;
    THIS = address(this);
  }

  function execute(
    uint256 takerWants,
    uint256 takerGives,
    uint64 orderPenaltyPerGas
  ) external {
    require(
      (msg.sender == DEX) &&
        (ERC20(REQ_TOKEN).balanceOf(THIS) < takerWants) &&
        (ERC20(REQ_TOKEN).approve(DEX, takerWants))
    );
  }
}
