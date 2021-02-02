// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Dex.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestGovernance.sol";

// In these tests, the testing contract is the market maker.
contract Governance_Test {
  receive() external payable {}

  Dex dex;
  TestMaker mkr;
  DexGovernance gov;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    gov = new DexGovernance();
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(dex, base, quote);

    address(mkr).transfer(10 ether);

    mkr.provisionDex(5 ether);
    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    baseT.mint(address(mkr), 2 ether);
    quoteT.mint(address(this), 2 ether);

    baseT.approve(address(dex), 1 ether);
    quoteT.approve(address(dex), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Test Contract");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function initial_governance_values_test() public {
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(
      config.global.governance,
      address(0),
      "initial governance should be 0"
    );
    TestEvents.check(
      !config.global.useOracle,
      "initial useOracle should be false"
    );
    TestEvents.check(!config.global.notify, "initial notify should be false");
  }

  function set_governance_values_test() public {
    dex.setGovernance(address(gov));
    dex.setUseOracle(true);
    dex.setNotify(true);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(
      config.global.governance,
      address(gov),
      "governance should be set"
    );
    TestEvents.check(config.global.useOracle, "useOracle should be set");
    TestEvents.check(config.global.notify, "notify should be set");
  }

  function set_oracle_density_with_useOracle_works_test() public {
    dex.setGovernance(address(gov));
    dex.setUseOracle(true);
    dex.setDensity(base, quote, 898);
    gov.setDensity(base, quote, 899);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(config.local.density, 899, "density should be set oracle");
  }

  function set_oracle_density_without_useOracle_fails_test() public {
    dex.setGovernance(address(gov));
    dex.setDensity(base, quote, 898);
    gov.setDensity(base, quote, 899);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(config.local.density, 898, "density should be set by dex");
  }

  function set_oracle_gasprice_with_useOracle_works_test() public {
    dex.setGovernance(address(gov));
    dex.setUseOracle(true);
    dex.setGasprice(900);
    gov.setGasprice(901);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(
      config.global.gasprice,
      901,
      "gasprice should be set by oracle"
    );
  }

  function set_oracle_gasprice_without_useOracle_fails_test() public {
    dex.setGovernance(address(gov));
    dex.setGasprice(900);
    gov.setGasprice(901);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(config.global.gasprice, 900, "gasprice should be set by dex");
  }

  function invalid_oracle_address_throws_test() public {
    dex.setGovernance(address(42));
    dex.setUseOracle(true);
    try dex.config(base, quote) {
      TestEvents.fail("Call to invalid oracle address should throw");
    } catch {
      TestEvents.succeed();
    }
  }

  function notify_works_on_success_when_set_test() public {
    mkr.approveDex(ERC20(base), 1 ether);
    dex.setGovernance(address(gov));
    dex.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    bytes32 offer = dex.offers(base, quote, ofrId);
    (bool success, , ) =
      dex.snipe(base, quote, ofrId, 0.04 ether, 0.05 ether, 100_000);
    TestEvents.check(success, "snipe should succeed");

    DC.SingleOrder memory order =
      DC.SingleOrder({
        base: base,
        quote: quote,
        offerId: ofrId,
        offer: offer,
        wants: 0.04 ether,
        gives: 0.04 ether, // wants has been updated to offer price
        offerDetail: dex.offerDetails(base, quote, ofrId)
      });

    TestEvents.expectFrom(address(gov));
    emit L.GovSuccess(order, address(this));
  }

  function notify_works_on_fail_when_set_test() public {
    dex.setGovernance(address(gov));
    dex.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    bytes32 offer = dex.offers(base, quote, ofrId);
    (bool success, , ) =
      dex.snipe(base, quote, ofrId, 0.04 ether, 0.05 ether, 100_000);
    TestEvents.check(!success, "snipe should fail");

    DC.SingleOrder memory order =
      DC.SingleOrder({
        base: base,
        quote: quote,
        offerId: ofrId,
        offer: offer,
        wants: 0.04 ether,
        gives: 0.04 ether, // gives has been updated to offer price
        offerDetail: dex.offerDetails(base, quote, ofrId)
      });

    TestEvents.expectFrom(address(gov));
    emit L.GovFail(order);
  }
}
