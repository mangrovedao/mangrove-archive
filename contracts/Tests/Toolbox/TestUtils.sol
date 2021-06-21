// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
// Encode structs
pragma abicoder v2;

import "../Agents/TestTaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/TestToken.sol";

import "./TestEvents.sol";
import "./Display.sol";
import "../../TMgv.sol";
import "../../MMgv.sol";

library TestUtils {
  struct Balances {
    uint mgvBalanceWei;
    uint mgvBalanceFees;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }
  enum Info {makerWants, makerGives, nextId, gasreq, gasprice}

  function getReason(bytes memory returnData)
    internal
    pure
    returns (string memory reason)
  {
    /* returnData for a revert(reason) is the result of
       abi.encodeWithSignature("Error(string)",reason)
       but abi.decode assumes the first 4 bytes are padded to 32
       so we repad them. See:
       https://github.com/ethereum/solidity/issues/6012
     */
    bytes memory pointer = abi.encodePacked(bytes28(0), returnData);
    uint len = returnData.length - 4;
    assembly {
      pointer := add(32, pointer)
      mstore(pointer, len)
    }
    reason = abi.decode(pointer, (string));
  }

  function isEmptyOB(
    Mangrove mgv,
    address base,
    address quote
  ) internal view returns (bool) {
    return mgv.best(base, quote) == 0;
  }

  function adminOf(Mangrove mgv) internal view returns (address) {
    return mgv.governance();
  }

  function getFee(
    Mangrove mgv,
    address base,
    address quote,
    uint price
  ) internal returns (uint) {
    return ((price * mgv.getConfig(base, quote).local.fee) / 10000);
  }

  function getProvision(
    Mangrove mgv,
    address base,
    address quote,
    uint gasreq
  ) internal returns (uint) {
    ML.Config memory config = mgv.getConfig(base, quote);
    return ((gasreq +
      config.local.overhead_gasbase +
      config.local.offer_gasbase) *
      uint(config.global.gasprice) *
      10**9);
  }

  function getProvision(
    Mangrove mgv,
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    ML.Config memory config = mgv.getConfig(base, quote);
    uint _gp;
    if (config.global.gasprice > gasprice) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = gasprice;
    }
    return ((gasreq +
      config.local.overhead_gasbase +
      config.local.offer_gasbase) *
      _gp *
      10**9);
  }

  function getOfferInfo(
    Mangrove mgv,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (ML.Offer memory offer, ML.OfferDetail memory offerDetail) =
      mgv.offerInfo(base, quote, offerId);
    if (!mgv.isLive(mgv.offers(base, quote, offerId))) {
      return 0;
    }
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
      return offer.gasprice;
    }
  }

  function hasOffer(
    Mangrove mgv,
    address base,
    address quote,
    uint offerId
  ) internal view returns (bool) {
    return (getOfferInfo(mgv, base, quote, Info.makerGives, offerId) > 0);
  }

  function makerOf(
    Mangrove mgv,
    address base,
    address quote,
    uint offerId
  ) internal view returns (address) {
    (, ML.OfferDetail memory od) = mgv.offerInfo(base, quote, offerId);
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

library MgvSetup {
  function setup(TestToken base, TestToken quote)
    external
    returns (Mangrove mgv)
  {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    mgv = new MMgv({gasprice: 40, gasmax: 1_000_000});

    mgv.activate(address(base), address(quote), 0, 100, 80_000, 20_000);
    mgv.activate(address(quote), address(base), 0, 100, 80_000, 20_000);

    return mgv;
  }

  function setup(
    TestToken base,
    TestToken quote,
    bool inverted
  ) external returns (Mangrove mgv) {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    if (inverted) {
      mgv = new TMgv({gasprice: 40, gasmax: 1_000_000});

      mgv.activate(address(base), address(quote), 0, 100, 80_000, 20_000);
      mgv.activate(address(quote), address(base), 0, 100, 80_000, 20_000);

      return mgv;
    } else {
      mgv = new MMgv({gasprice: 40, gasmax: 1_000_000});

      mgv.activate(address(base), address(quote), 0, 100, 80_000, 20_000);
      mgv.activate(address(quote), address(base), 0, 100, 80_000, 20_000);

      return mgv;
    }
  }
}

library MakerSetup {
  function setup(
    Mangrove mgv,
    address base,
    address quote,
    uint failer // 1 shouldFail, 2 shouldRevert
  ) external returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20(base), IERC20(quote));
    tm.shouldFail(failer == 1);
    tm.shouldRevert(failer == 2);
    return (tm);
  }

  function setup(
    Mangrove mgv,
    address base,
    address quote
  ) external returns (TestMaker) {
    return new TestMaker(mgv, IERC20(base), IERC20(quote));
  }
}

library MakerDeployerSetup {
  function setup(
    Mangrove mgv,
    address base,
    address quote
  ) external returns (MakerDeployer) {
    TestEvents.not0x(address(mgv));
    return (new MakerDeployer(mgv, base, quote));
  }
}

library TakerSetup {
  function setup(
    Mangrove mgv,
    address base,
    address quote
  ) external returns (TestTaker) {
    TestEvents.not0x(address(mgv));
    return new TestTaker(mgv, IERC20(base), IERC20(quote));
  }
}
