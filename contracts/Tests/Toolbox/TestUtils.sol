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
    address atk,
    address btk
  ) internal view returns (bool) {
    (DC.Offer memory offer, ) =
      dex.getOfferInfo(atk, btk, dex.bests(atk, btk), true);
    return !DC.isOffer(offer);
  }

  function adminOf(Dex dex) internal view returns (address) {
    return dex.admin();
  }

  function getFee(
    Dex dex,
    address atk,
    address btk,
    uint price
  ) internal view returns (uint) {
    return ((price * dex.config(atk, btk).fee) / 10000);
  }

  function getProvision(
    Dex dex,
    address atk,
    address btk,
    uint gasreq
  ) internal view returns (uint) {
    DC.Config memory config = dex.config(atk, btk);
    return ((gasreq + config.gasbase) * config.gasprice);
  }

  function getOfferInfo(
    Dex dex,
    address atk,
    address btk,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (DC.Offer memory offer, DC.OfferDetail memory offerDetail) =
      dex.getOfferInfo(atk, btk, offerId, true);
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
    address atk,
    address btk,
    uint offerId
  ) internal view returns (bool) {
    return (getOfferInfo(dex, atk, btk, Info.makerGives, offerId) > 0);
  }

  function makerOf(
    Dex dex,
    address atk,
    address btk,
    uint offerId
  ) internal view returns (address) {
    (, DC.OfferDetail memory od) = dex.getOfferInfo(atk, btk, offerId, true);
    return od.maker;
  }

  function _snipe(
    TestTaker taker,
    uint snipedId,
    uint orderAmount
  ) external returns (bool) {
    return (taker.take(snipedId, orderAmount));
  }

  function snipeWithGas(
    TestTaker taker,
    uint snipedId,
    uint orderAmount
  ) internal returns (bool) {
    bytes memory retdata =
      TestEvents.execWithCost(
        "snipe",
        address(TestUtils),
        abi.encodeWithSelector(
          TestUtils._snipe.selector,
          taker,
          snipedId,
          orderAmount
        )
      );
    return (abi.decode(retdata, (bool)));
  }

  function _newOffer(
    TestMaker maker,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) external returns (uint) {
    return (maker.newOffer(wants, gives, gasreq, pivotId));
  }

  function newOfferWithGas(
    TestMaker maker,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) internal returns (uint) {
    bytes memory retdata =
      TestEvents.execWithCost(
        "newOffer",
        address(TestUtils),
        abi.encodeWithSelector(
          TestUtils._newOffer.selector,
          maker,
          wants,
          gives,
          gasreq,
          pivotId
        )
      );
    return (abi.decode(retdata, (uint)));
  }

  function _marketOrder(
    TestTaker taker,
    uint takerWants,
    uint takerGives
  ) external {
    taker.marketOrder(takerWants, takerGives);
  }

  function marketOrderWithGas(
    TestTaker taker,
    uint takerWants,
    uint takerGives
  ) internal {
    TestEvents.execWithCost(
      "marketOrder",
      address(TestUtils),
      abi.encodeWithSelector(
        TestUtils._marketOrder.selector,
        taker,
        takerWants,
        takerGives
      )
    );
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
  function setup(TestToken aToken, TestToken bToken)
    external
    returns (Dex dex)
  {
    TestEvents.not0x(address(aToken));
    TestEvents.not0x(address(bToken));
    dex = new Dex({
      gasprice: 40 * 10**9,
      gasbase: 30_000,
      gasmax: 1_000_000,
      takerLends: true
    });

    dex.setActive(address(aToken), address(bToken), true);
    dex.setDensity(address(aToken), address(bToken), 100);

    return dex;
  }
}

library MakerSetup {
  function setup(
    Dex dex,
    address atk,
    address btk,
    bool shouldFail
  ) external returns (TestMaker) {
    return new TestMaker(dex, atk, btk, shouldFail);
  }
}

library MakerDeployerSetup {
  function setup(
    Dex dex,
    address atk,
    address btk
  ) external returns (MakerDeployer) {
    TestEvents.not0x(address(dex));
    return (new MakerDeployer(dex, atk, btk));
  }
}

library TakerSetup {
  function setup(
    Dex dex,
    address atk,
    address btk
  ) external returns (TestTaker) {
    TestEvents.not0x(address(dex));
    return new TestTaker(dex, atk, btk);
  }
}
