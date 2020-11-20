pragma experimental ABIEncoderV2;

import "../../Dex.sol";
import "../../DexDeployer.sol";
import "../Agents/MakerDeployer.sol";

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
    bytes memory retdata = Test.execWithCost(
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
    bytes memory retdata = Test.execWithCost(
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
    Test.execWithCost(
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
    Test.not0x(address(aToken));
    Test.not0x(address(bToken));
    DexDeployer deployer = new DexDeployer(address(this));

    deployer.deploy({
      density: 100,
      gasprice: 40 * 10**9,
      gasbase: 30000,
      gasmax: 1000000,
      ofrToken: address(aToken),
      reqToken: address(bToken)
    });
    return deployer.dexes(address(aToken), address(bToken));
  }
}

library MakerSetup {
  function setup(Dex dex, bool shouldFail) external returns (TestMaker) {
    return new TestMaker(dex, shouldFail);
  }
}

library MakerDeployerSetup {
  function setup(Dex dex) external returns (MakerDeployer) {
    Test.not0x(address(dex));
    return (new MakerDeployer(dex));
  }
}

library TakerSetup {
  function setup(Dex dex) external returns (TestTaker) {
    Test.not0x(address(dex));
    return new TestTaker(dex);
  }
}
