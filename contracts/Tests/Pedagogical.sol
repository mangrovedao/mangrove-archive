// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
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

  AbstractMangrove mgv;
  TestToken bat;
  TestToken dai;
  TestTaker tkr;
  TestMaker mkr;
  Compound compound;

  function example_1_offerbook_test() public {
    setupMakerBasic();

    Display.log("Filling book");

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

    //logBook
    Display.logOfferBook(mgv, address(bat), address(dai), 3);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function example_2_markerOrder_test() public {
    example_1_offerbook_test();

    Display.log(
      "Market order. Taker wants 2.7 exaunits and gives 3.5 exaunits."
    );
    (uint got, uint gave) =
      tkr.marketOrder({wants: 2.7 ether, gives: 3.5 ether});
    Display.log("Market order ended. Got / gave", got, gave);

    Display.logOfferBook(mgv, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function example_3_redeem_test() public {
    setupMakerCompound();

    Display.log("Maker posts an offer for 1 exaunit");
    uint ofr =
      mkr.newOffer({
        wants: 1 ether,
        gives: 1 ether,
        gasreq: 600_000,
        pivotId: 0
      });

    Display.logOfferBook(mgv, address(bat), address(dai), 1);
    Display.logBalances(
      bat,
      dai,
      address(mkr),
      address(tkr),
      address(compound)
    );
    Display.logBalances(
      ERC20BL(compound.c(bat)),
      ERC20BL(compound.c(dai)),
      address(mkr)
    );

    Display.log("Taker takes offer for 0.3 exaunits");
    bool took = tkr.take(ofr, 0.3 ether);
    if (took) {
      Display.log("Take successful");
    } else {
      Display.log("Take failed");
    }

    Display.logOfferBook(mgv, address(bat), address(dai), 1);
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

    Display.log("Maker posts 1 offer");
    mkr.newOffer({wants: 1 ether, gives: 1 ether, gasreq: 400_000, pivotId: 0});

    Display.logOfferBook(mgv, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));

    Display.log(
      "Market order begins. Maker will be called back and reinsert its offer"
    );
    (uint got, uint gave) = tkr.marketOrder({wants: 1 ether, gives: 1 ether});
    Display.log("Market order complete. got / gave:", got, gave);

    Display.logOfferBook(mgv, address(bat), address(dai), 1);
    Display.logBalances(bat, dai, address(mkr), address(tkr));
  }

  function _beforeAll() public {
    bat = new TestToken({
      admin: address(this),
      name: "Basic attention token",
      symbol: "BAT"
    });

    dai = new TestToken({admin: address(this), name: "Dai", symbol: "DAI"});

    mgv = new Mangrove({gasprice: 40, gasmax: 1_000_000});

    // activate a market where taker buys BAT using DAI
    mgv.activate({
      base: address(bat),
      quote: address(dai),
      fee: 0,
      density: 100,
      overhead_gasbase: 30_000,
      offer_gasbase: 10_000
    });

    tkr = new TestTaker({mgv: mgv, base: bat, quote: dai});

    mgv.fund{value: 10 ether}(address(this));

    dai.mint({amount: 10 ether, to: address(tkr)});
    tkr.approveMgv({amount: 10 ether, token: dai});

    Display.register({addr: msg.sender, name: "Test Runner"});
    Display.register({addr: address(this), name: "Testing Contract"});
    Display.register({addr: address(bat), name: "BAT"});
    Display.register({addr: address(dai), name: "DAI"});
    Display.register({addr: address(mgv), name: "mgv"});
    Display.register({addr: address(tkr), name: "taker"});
  }

  function setupMakerBasic() internal {
    mkr = new Maker_basic({mgv: mgv, base: bat, quote: dai});

    Display.register({addr: address(mkr), name: "maker-basic"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionMgv({amount: 5 ether});
    bat.mint({amount: 10 ether, to: address(mkr)});
  }

  function setupMakerCompound() internal {
    compound = new Compound();
    Display.register(address(compound), "compound");
    Display.register(address(compound.c(bat)), "cBAT");
    Display.register(address(compound.c(dai)), "cDAI");

    Maker_compound _mkr =
      new Maker_compound({mgv: mgv, base: bat, quote: dai, compound: compound});

    mkr = _mkr;

    bat.mint({amount: 10 ether, to: address(mkr)});
    _mkr.useCompound();

    Display.register({addr: address(mkr), name: "maker-compound"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionMgv({amount: 5 ether});
  }

  function setupMakerCallback() internal {
    Display.log("Setting up maker with synchronous callback");
    mkr = new Maker_callback({mgv: mgv, base: bat, quote: dai});

    Display.register({addr: address(mkr), name: "maker-callback"});

    // testing contract starts with 1000 ETH
    address(mkr).transfer(10 ether);
    mkr.provisionMgv({amount: 5 ether});

    bat.mint({amount: 10 ether, to: address(mkr)});
  }
}

// Provisioned.
// Sends amount to taker.
contract Maker_basic is TestMaker {
  constructor(
    AbstractMangrove mgv,
    ERC20BL base,
    ERC20BL quote
  ) TestMaker(mgv, base, quote) {
    approveMgv(base, 500 ether);
  }

  function makerTrade(ML.SingleOrder calldata)
    public
    pure
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    //ERC20(order.base).transfer({recipient: taker, amount: order.wants});
  }
}

// Not provisioned.
// Redeems money from fake-Compound
contract Maker_compound is TestMaker {
  Compound _compound;

  constructor(
    AbstractMangrove mgv,
    ERC20BL base,
    ERC20BL quote,
    Compound compound
  ) TestMaker(mgv, base, quote) {
    _compound = compound;
    approveMgv(base, 500 ether);
    base.approve(address(compound), 500 ether);
    quote.approve(address(compound), 500 ether);
  }

  function useCompound() external {
    Display.log("Maker deposits 10 exaunits at Compound.");
    _compound.mint(ERC20BL(_base), 10 ether);
  }

  function makerTrade(ML.SingleOrder calldata order)
    public
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    _compound.mint({token: ERC20BL(order.quote), amount: order.gives});
    Display.log("Maker redeems from Compound.");
    _compound.redeem({
      token: ERC20BL(order.base),
      amount: order.wants,
      to: address(this)
    });
  }
}

// Provisioned.
// Reinserts the offer if necessary.
contract Maker_callback is TestMaker {
  constructor(
    AbstractMangrove mgv,
    ERC20BL base,
    ERC20BL quote
  ) TestMaker(mgv, base, quote) {
    approveMgv(base, 500 ether);
  }

  function makerTrade(ML.SingleOrder calldata)
    public
    pure
    override
    returns (bytes32 ret)
  {
    ret; // silence compiler warning
    //ERC20BL(order.base).transfer({recipient: taker, amount: order.wants});
  }

  uint volume = 1 ether;
  uint price = 340; // in %
  uint gasreq = 400_000;

  function makerPosthook(ML.SingleOrder calldata order, ML.OrderResult calldata)
    external
    override
  {
    Display.log("Reinserting offer...");
    AbstractMangrove mgv = AbstractMangrove(msg.sender);
    mgv.updateOffer({
      base: order.base,
      quote: order.quote,
      wants: (price * volume) / 100,
      gives: volume,
      gasreq: gasreq,
      gasprice: 0,
      pivotId: 0,
      offerId: order.offerId
    });
  }
}
