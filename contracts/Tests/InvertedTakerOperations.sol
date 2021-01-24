// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract InvertedTakerOperations_Test is ITaker {
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  Dex dex;
  TestMaker mkr;

  receive() external payable {}

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT, true);
    mkr = MakerSetup.setup(dex, base, quote);

    address(mkr).transfer(10 ether);
    mkr.provisionDex(1 ether);

    baseT.mint(address(mkr), 5 ether);
    quoteT.mint(address(this), 5 ether);
    quoteT.approve(address(dex), 5 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
  }

  function takerTrade(
    address,
    address,
    uint totalGot,
    uint
  ) public override {
    TestEvents.eq(totalGot, 0.2 ether, "totalGot should be sum of flashloans");
    TestEvents.eq(
      IERC20(base).balanceOf(address(this)),
      0.2 ether,
      "taker should have received sum of flashloans"
    );
  }

  function taker_gets_sum_of_borrows_in_execute_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    dex.simpleMarketOrder(base, quote, 0.2 ether, 0.2 ether);
  }
}
