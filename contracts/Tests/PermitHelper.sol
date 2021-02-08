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

/* THIS IS NOT A `test-solidity` TEST FILE */
/* See test/permit.js, this helper sets up a dex for the javascript tester of the permit functionality */

contract PermitHelper {
  receive() external payable {}

  Dex dex;
  address base;
  address quote;

  constructor() {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    quoteT.mint(tx.origin, 2 ether);

    baseT.approve(address(dex), 1 ether);

    Display.register(tx.origin, "Permit signer");
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

  function testPermit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    try
      dex.permittedSnipe(base, quote, 1, 1 ether, 1 ether, 300_000, tx.origin)
    {
      revert("Snipe should revert");
    } catch Error(string memory) {
      dex.permit(
        base,
        quote,
        tx.origin,
        address(this),
        value,
        deadline,
        v,
        r,
        s
      );

      if (dex.allowances(base, quote, tx.origin, address(this)) != value) {
        revert("Allowance not set");
      }

      (bool success, uint takerGot, uint takerGave) =
        dex.permittedSnipe(
          base,
          quote,
          1,
          1 ether,
          1 ether,
          300_000,
          tx.origin
        );
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
        dex.allowances(base, quote, tx.origin, address(this)) !=
        (value - 1 ether)
      ) {
        revert("Allowance incorrectly decreased");
      }
    }
  }
}
