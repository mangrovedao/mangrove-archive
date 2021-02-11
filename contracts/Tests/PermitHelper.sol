// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

/* *********************************************** */
/* THIS IS NOT A `hardhat test-solidity` TEST FILE */
/* *********************************************** */

/* See test/permit.js, this helper sets up a dex for the javascript tester of the permit functionality */

contract PermitHelper is IMaker {
  receive() external payable {}

  Dex dex;
  address base;
  address quote;

  function makerTrade(DC.SingleOrder calldata)
    external
    override
    returns (bytes32)
  {}

  function makerPosthook(DC.SingleOrder calldata, DC.OrderResult calldata)
    external
    override
  {}

  constructor() payable {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    quoteT.mint(msg.sender, 2 ether);

    baseT.approve(address(dex), 1 ether);

    Display.register(msg.sender, "Permit signer");
    Display.register(address(this), "Permit Helper");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");

    dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
  }

  function dexAddress() external view returns (address) {
    return address(dex);
  }

  function baseAddress() external view returns (address) {
    return base;
  }

  function quoteAddress() external view returns (address) {
    return quote;
  }

  function no_allowance() external {
    try dex.snipeFor(base, quote, 1, 1 ether, 1 ether, 300_000, msg.sender) {
      revert("snipeFor without allowance should revert");
    } catch Error(string memory reason) {
      if (keccak256(bytes(reason)) != keccak256("dex/lowAllowance")) {
        revert("revert when no allowance should be due to no allowance");
      }
    }
  }

  function wrong_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    try
      dex.permit({
        base: base,
        quote: quote,
        owner: msg.sender,
        spender: address(this),
        value: value,
        deadline: deadline,
        v: v,
        r: r,
        s: s
      })
    {
      revert("Permit with bad v,r,s should revert");
    } catch Error(string memory reason) {
      if (
        keccak256(bytes(reason)) != keccak256("dex/permit/invalidSignature")
      ) {
        revert("permit failed, but signature should be deemed invalid");
      }
    }
  }

  function expired_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    try
      dex.permit({
        base: base,
        quote: quote,
        owner: msg.sender,
        spender: address(this),
        value: value,
        deadline: deadline,
        v: v,
        r: r,
        s: s
      })
    {
      revert("Permit with expired deadline should revert");
    } catch Error(string memory reason) {
      if (keccak256(bytes(reason)) != keccak256("dex/permit/expired")) {
        revert("permit failed, but deadline should be deemed expired");
      }
    }
  }

  function good_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    dex.permit(
      base,
      quote,
      msg.sender,
      address(this),
      value,
      deadline,
      v,
      r,
      s
    );

    if (dex.allowances(base, quote, msg.sender, address(this)) != value) {
      revert("Allowance not set");
    }

    (bool success, uint takerGot, uint takerGave) =
      dex.snipeFor(base, quote, 1, 1 ether, 1 ether, 300_000, msg.sender);
    if (!success) {
      revert("Snipe should succeed");
    }
    if (takerGot != 1 ether) {
      revert("takerGot should be 1 ether");
    }

    if (takerGave != 1 ether) {
      revert("takerGave should be 1 ether");
    }

    if (
      dex.allowances(base, quote, msg.sender, address(this)) !=
      (value - 1 ether)
    ) {
      revert("Allowance incorrectly decreased");
    }
  }
}
