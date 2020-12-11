// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../Agents/TestTaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/TestToken.sol";

import "./TestEvents.sol";
import "./Display.sol";

library TestUtils {
  struct Balances {
    uint dexBalanceWei;
    uint dexBalanceFees;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }
  enum Info {makerWants, makerGives, nextId, gasreq, gasprice}

  function isEmptyOB(
    Dex dex,
    address base,
    address quote
  ) internal view returns (bool) {
    (DC.Offer memory offer, ) =
      dex.getOfferInfo(base, quote, dex.bests(base, quote), true);
    return !DC.isOffer(offer);
  }

  function adminOf(Dex dex) internal view returns (address) {
    return dex.admin();
  }

  function getFee(
    Dex dex,
    address base,
    address quote,
    uint price
  ) internal view returns (uint) {
    return ((price * dex.config(base, quote).fee) / 10000);
  }

  function getProvision(
    Dex dex,
    address base,
    address quote,
    uint gasreq
  ) internal view returns (uint) {
    DC.Config memory config = dex.config(base, quote);
    return ((gasreq + config.gasbase) * config.gasprice);
  }

  function getOfferInfo(
    Dex dex,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (DC.Offer memory offer, DC.OfferDetail memory offerDetail) =
      dex.getOfferInfo(base, quote, offerId, true);
    if (infKey == Info.makerWants) {
      return offer.wants;
    }
    if (infKey == Info.makerGives) {
      return offer.gives;
    }
    if (infKey == Info.nextId) {
      return offer.next;
    }
    if (infKey == Info.gasreq) {
      return offerDetail.gasreq;
    } else {
      return offerDetail.gasprice;
    }
  }

  function hasOffer(
    Dex dex,
    address base,
    address quote,
    uint offerId
  ) internal view returns (bool) {
    return (getOfferInfo(dex, base, quote, Info.makerGives, offerId) > 0);
  }

  function makerOf(
    Dex dex,
    address base,
    address quote,
    uint offerId
  ) internal view returns (address) {
    (, DC.OfferDetail memory od) = dex.getOfferInfo(base, quote, offerId, true);
    return od.maker;
  }
}

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

library TokenSetup {
  function setup(string memory name, string memory ticker)
    external
    returns (TestToken)
  {
    return new TestToken(address(this), name, ticker);
  }
}

library DexSetup {
  function setup(TestToken base, TestToken quote) external returns (Dex dex) {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    dex = new Dex({
      gasprice: 40 * 10**9,
      gasbase: 30_000,
      gasmax: 1_000_000,
      takerLends: true
    });

    dex.setActive(address(base), address(quote), true);
    dex.setDensity(address(base), address(quote), 100);

    return dex;
  }
}

library MakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote,
    bool shouldFail
  ) external returns (TestMaker) {
    return new TestMaker(dex, base, quote, shouldFail);
  }
}

library MakerDeployerSetup {
  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (MakerDeployer) {
    TestEvents.not0x(address(dex));
    return (new MakerDeployer(dex, base, quote));
  }
}

library TakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (TestTaker) {
    TestEvents.not0x(address(dex));
    return new TestTaker(dex, base, quote);
  }
}
