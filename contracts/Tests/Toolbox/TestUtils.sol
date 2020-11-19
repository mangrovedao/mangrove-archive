pragma experimental ABIEncoderV2;

import "../../Dex.sol";

import "./Display.sol";
import "../Agents/TestTaker.sol";
import "../Agents/TestMaker.sol";

import "./TestEvents.sol";

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

  function getFee(Dex dex, uint price) internal view returns (uint) {
    return ((price * dex.getConfigUint(ConfigKey.fee)) / 10000);
  }

  function getProvision(Dex dex, uint gasreq) internal view returns (uint) {
    return ((gasreq + dex.getConfigUint(ConfigKey.gasbase)) *
      dex.getConfigUint(ConfigKey.gasprice));
  }

  function getOfferInfo(
    Dex dex,
    Info infKey,
    uint offerId
  ) internal returns (uint) {
    (Offer memory offer, OfferDetail memory offerDetail) = dex.getOfferInfo(
      offerId,
      true
    );
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

  function makerOf(Dex dex, uint offerId) internal returns (address) {
    (, OfferDetail memory od) = dex.getOfferInfo(offerId, true);
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
    bytes memory retdata = TestEvents.execWithCost(
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
    bytes memory retdata = TestEvents.execWithCost(
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
