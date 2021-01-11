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
import "./Agents/Compound.sol";

contract Pedagogical_Test {
  receive() external payable {}

  Dex dex;
  TestToken bat;
  TestToken dai;
  TestTaker tkr;
  TestMaker mkr;
  Compound compound;

  function example_1_offerbook_test() public {
    setupMakerBasic();

    mkr.newOffer({wants: 1 ether, gives: 1 ether, gasreq: 300_000, pivotId: 0});

    mkr.newOffer({
      wants: 1.1 ether,
      gives: 1 ether,
      gasreq: 300_000,
      pivotId: 0
    });

    mkr.newOffer({
      wants: 1.2 ether,
      gives: 1 ether,
      gasreq: 300_000,
      pivotId: 0
    });

    Display.logOfferBook(dex, address(bat), address(dai), 3);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function example_2_markerOrder_test() public {
    example_1_offerbook_test();

    tkr.marketOrder({wants: 2.7 ether, gives: 3.5 ether});

    Display.logOfferBook(dex, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function example_3_redeem_test() public {
    setupMakerCompound();

    uint ofr =
      mkr.newOffer({
        wants: 1 ether,
        gives: 1 ether,
        gasreq: 600_000,
        pivotId: 0
      });

    Display.logOfferBook(dex, address(bat), address(dai), 1);
    Display.logBalances(
      bat,
      dai,
      address(mkr),
      address(tkr),
      address(compound)
    );
    Display.logBalances(
      ERC20(compound.c(bat)),
      ERC20(compound.c(dai)),
      address(mkr)
    );

    tkr.take(ofr, 0.3 ether);

    Display.logOfferBook(dex, address(bat), address(dai), 1);
    Display.logBalances(
      bat,
      dai,
      address(mkr),
      address(tkr),
      address(compound)
    );
  }

  function example_4_callback_test() public {
    setupMakerCallback();

    mkr.newOffer({wants: 1 ether, gives: 1 ether, gasreq: 400_000, pivotId: 0});

    Display.logOfferBook(dex, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));

    tkr.marketOrder({wants: 1 ether, gives: 1 ether});

    Display.logOfferBook(dex, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function _beforeAll() public {
    bat = new TestToken({
      admin: address(this),
      name: "Basic attention token",
      symbol: "BAT"
    });

    dai = new TestToken({admin: address(this), name: "Dai", symbol: "DAI"});

    dex = new NormalDex({
      gasprice: 40 * 10**9,
      gasbase: 30_000,
      gasmax: 1_000_000
    });

    // activate a market where taker buys BAT using DAI
    dex.activate({
      base: address(bat),
      quote: address(dai),
      fee: 0,
      density: 100
    });

    tkr = new TestTaker({dex: dex, base: bat, quote: dai});

    dex.fund{value: 10 ether}();

    dai.mint({amount: 10 ether, to: address(tkr)});
    tkr.approveDex({amount: 10 ether, token: dai});

    Display.register({addr: msg.sender, name: "Test Runner"});
    Display.register({addr: address(this), name: "Testing Contract"});
    Display.register({addr: address(bat), name: "BAT"});
    Display.register({addr: address(dai), name: "DAI"});
    Display.register({addr: address(dex), name: "dex"});
    Display.register({addr: address(tkr), name: "taker"});
  }

  function setupMakerBasic() internal {
    mkr = new Maker_basic({dex: dex, base: bat, quote: dai});

    Display.register({addr: address(mkr), name: "maker-basic"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionDex({amount: 5 ether});
    bat.mint({amount: 10 ether, to: address(mkr)});
  }

  function setupMakerCompound() internal {
    compound = new Compound();
    Display.register(address(compound), "compound");
    Display.register(address(compound.c(bat)), "cBAT");
    Display.register(address(compound.c(dai)), "cDAI");

    Maker_compound _mkr =
      new Maker_compound({dex: dex, base: bat, quote: dai, compound: compound});

    mkr = _mkr;

    bat.mint({amount: 10 ether, to: address(mkr)});
    _mkr.useCompound();

    Display.register({addr: address(mkr), name: "maker-compound"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionDex({amount: 5 ether});
  }

  function setupMakerCallback() internal {
    mkr = new Maker_callback({dex: dex, base: bat, quote: dai});

    Display.register({addr: address(mkr), name: "maker-callback"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionDex({amount: 5 ether});

    bat.mint({amount: 10 ether, to: address(mkr)});
  }
}

// Provisioned.
// Sends amount to taker.
contract Maker_basic is TestMaker {
  constructor(
    Dex dex,
    ERC20 base,
    ERC20 quote
  ) TestMaker(dex, base, quote) {}

  function makerTrade(IMaker.Trade calldata trade)
    public
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    ERC20(trade.base).transfer({
      recipient: trade.taker,
      amount: trade.takerWants
    });
  }
}

// Not provisioned.
// Redeems money from fake-Compound
contract Maker_compound is TestMaker {
  Compound _compound;

  constructor(
    Dex dex,
    ERC20 base,
    ERC20 quote,
    Compound compound
  ) TestMaker(dex, base, quote) {
    _compound = compound;
    base.approve(address(compound), 500 ether);
    quote.approve(address(compound), 500 ether);
  }

  function useCompound() external {
    _compound.mint(ERC20(_base), 4 ether);
  }

  function makerTrade(IMaker.Trade calldata trade)
    public
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    _compound.redeem({
      token: ERC20(trade.base),
      amount: trade.takerWants,
      to: trade.taker
    });
    _compound.mint({token: ERC20(trade.quote), amount: trade.takerGives});
  }
}

// Provisioned.
// Reinserts the offer if necessary.
contract Maker_callback is TestMaker {
  constructor(
    Dex dex,
    ERC20 base,
    ERC20 quote
  ) TestMaker(dex, base, quote) {}

  function makerTrade(IMaker.Trade calldata trade)
    public
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    ERC20(trade.base).transfer({
      recipient: trade.taker,
      amount: trade.takerWants
    });
  }

  uint volume = 1 ether;
  uint price = 340; // in %
  uint gasreq = 400_000;

  function makerHandoff(IMaker.Handoff calldata handoff) public override {
    Dex dex = Dex(msg.sender);
    if (handoff.offerDeleted) {
      dex.updateOffer({
        base: handoff.base,
        quote: handoff.quote,
        wants: (price * volume) / 100,
        gives: volume,
        gasreq: gasreq,
        pivotId: 0,
        offerId: handoff.offerId
      });
    }
  }
}
