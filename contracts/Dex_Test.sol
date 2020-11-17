// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./Test.sol";
import "./DexDeployer.sol";
import "./Dex.sol";
import "./DexCommon.sol";
import "./TestToken.sol";
import "./TestMaker.sol";
import "./MakerDeployer.sol";
import "./TestTaker.sol";
import "./interfaces.sol";
import "hardhat/console.sol";
import "./Display.sol";

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

library DexPre0 {
  function setup() external returns (TestToken, TestToken) {
    return (
      new TestToken(address(this), "A", "$A"),
      new TestToken(address(this), "B", "$B")
    );
  }
}

library DexPre1 {
  function setup(TestToken aToken, TestToken bToken)
    external
    returns (Dex dex)
  {
    Test.testNot0x(address(aToken));
    Test.testNot0x(address(bToken));
    DexDeployer deployer = new DexDeployer(address(this));

    deployer.deploy({
      initialDustPerGasWanted: 100,
      initialGasprice: 30000,
      initialGasmax: 1000000,
      ofrToken: address(aToken),
      reqToken: address(bToken)
    });
    return deployer.dexes(address(aToken), address(bToken));
  }
}

library DexPre2 {
  function setup(Dex dex) external returns (MakerDeployer) {
    Test.testNot0x(address(dex));
    return (new MakerDeployer(dex));
  }
}

library DexPre3 {
  function setup(Dex dex) external returns (TestTaker) {
    Test.testNot0x(address(dex));
    return new TestTaker(dex);
  }
}

library TestUtils {
  struct Balances {
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

  function getOfferInfo(
    Dex dex,
    Info infKey,
    uint offerId
  ) internal returns (uint) {
    (
      uint makerWants,
      uint makerGives,
      uint nextId,
      uint gasreq,
      uint gasbase,
      uint gasprice,

    ) = dex.getOfferInfo(offerId);
    if (infKey == Info.makerWants) {
      return makerWants;
    }
    if (infKey == Info.makerGives) {
      return makerGives;
    }
    if (infKey == Info.nextId) {
      return nextId;
    }
    if (infKey == Info.gasreq) {
      return gasreq;
    } else {
      return gasprice;
    }
  }

  function makerOf(Dex dex, uint offerId) internal returns (address) {
    (, , , , , , address maker) = dex.getOfferInfo(offerId);
    return maker;
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

library TestInsert {
  function run(
    TestUtils.Balances storage balances,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) public returns (uint[] memory) {
    // each maker publishes an offer
    uint[] memory offerOf = new uint[](makers.length());
    offerOf[1] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(1),
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 7000,
      pivotId: 0
    });
    offerOf[2] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(2),
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 8000,
      pivotId: 1
    });
    offerOf[3] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(3),
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 9000,
      pivotId: 72
    });

    offerOf[0] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(0), //failer
      wants: 20 ether,
      gives: 10 ether,
      gasreq: dex.getConfigUint(ConfigKey.gasmax),
      pivotId: 0
    });
    //Checking makers have correctly provisoned their offers
    uint minGas = dex.getConfigUint(ConfigKey.gasbase);
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i = TestUtils.getOfferInfo(
        dex,
        TestUtils.Info.gasreq,
        offerOf[i]
      );
      uint provision_i = (gasreq_i + minGas) *
        dex.getConfigUint(ConfigKey.gasprice);
      Test.testEq(
        dex.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        Display.append("Incorrect wei balance for maker ", Display.uint2str(i))
      );
      return offerOf;
    }

    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = dex.best();
    uint expected_maker = 3;
    while (offerId != 0) {
      (, , uint nextId, , , , address makerAddr) = dex.getOfferInfo(offerId);
      Test.testEq(
        makerAddr,
        address(makers.getMaker(expected_maker)),
        Display.append(
          "Incorrect maker address at offer ",
          Display.uint2str(offerId)
        )
      );

      expected_maker -= 1;
      offerId = nextId;
    }
  }
}

library TestSnipe {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint orderAmount = 0.3 ether;
    uint snipedId = 2;
    TestMaker maker = makers.getMaker(snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=dex.getOfferInfo(2);
    //---------------SNIPE------------------//
    bool success = TestUtils.snipeWithGas(taker, snipedId, orderAmount);
    Test.testTrue(success, "snipe should be a success");

    Test.testEq(
      aToken.balanceOf(address(dex)), //actual
      balances.dexBalanceFees + TestUtils.getFee(dex, orderAmount), //expected
      "incorrect Dex A balance"
    );
    Test.testEq(
      bToken.balanceOf(address(taker)),
      balances.takerBalanceB -
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect taker B balance"
    );
    Test.testEq(
      aToken.balanceOf(address(taker)), // actual
      balances.takerBalanceA + orderAmount - TestUtils.getFee(dex, orderAmount), // expected
      "incorrect taker A balance"
    );

    Test.testEq(
      aToken.balanceOf(address(maker)),
      balances.makersBalanceA[snipedId] - orderAmount,
      "incorrect maker A balance"
    );
    Test.testEq(
      bToken.balanceOf(address(maker)),
      balances.makersBalanceB[snipedId] +
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (uint makerWants, uint makerGives, , , , , ) = dex.getOfferInfo(snipedId);
    Test.testEq(
      makerGives,
      offers[snipedId][TestUtils.Info.makerGives] - orderAmount,
      "Incorrect residual offer (gives)"
    );
    Test.testEq(
      makerWants,
      (offers[snipedId][TestUtils.Info.makerWants] *
        (offers[snipedId][TestUtils.Info.makerGives] - orderAmount)) /
        offers[snipedId][TestUtils.Info.makerGives],
      "Incorrect residual offer (wants)"
    );
  }
}

library TestMarketOrder {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    TestUtils.marketOrderWithGas(taker, takerWants, takerGives);

    // Checking Makers balances
    for (uint i = 2; i < 4; i++) {
      // offers 2 and 3 were consumed entirely
      Test.testEq(
        aToken.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceA[i] - offers[i][TestUtils.Info.makerGives],
        Display.append("Incorrect A balance for maker ", Display.uint2str(i))
      );
      Test.testEq(
        bToken.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceB[i] + offers[i][TestUtils.Info.makerWants],
        Display.append("Incorrect B balance for maker ", Display.uint2str(i))
      );
    }
    uint leftTkrWants = takerWants -
      (offers[2][TestUtils.Info.makerGives] +
        offers[3][TestUtils.Info.makerGives]);
    uint leftMkrWants = (offers[1][TestUtils.Info.makerWants] * leftTkrWants) /
      offers[1][TestUtils.Info.makerGives];

    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceA[1] - leftTkrWants,
      "Incorrect A balance for maker 1"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + leftMkrWants,
      "Incorrect B balance for maker 1"
    );

    // Checking taker balance
    Test.testEq(
      aToken.balanceOf(address(taker)), // actual
      balances.takerBalanceA + takerWants - TestUtils.getFee(dex, takerWants), // expected
      "incorrect taker A balance"
    );

    Test.testEq(
      bToken.balanceOf(address(taker)), // actual
      balances.takerBalanceB -
        (offers[3][TestUtils.Info.makerWants] +
          offers[2][TestUtils.Info.makerWants] +
          leftMkrWants), // expected
      "incorrect taker B balance"
    );

    // Checking DEX Fee Balance
    Test.testEq(
      aToken.balanceOf(address(dex)), //actual
      balances.dexBalanceFees + TestUtils.getFee(dex, takerWants), //expected
      "incorrect Dex balances"
    );
  }
}

library TestCollectFailingOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    uint failingOfferId,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    // executing failing offer
    try taker.take(failingOfferId, 0.5 ether) returns (bool success) {
      Test.testTrue(!success, "Failer should fail");
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      Test.testFail(err);
    }
  }
}

contract Dex_Test {
  Dex dex;
  TestTaker taker;
  MakerDeployer makers;
  TestToken aToken;
  TestToken bToken;
  TestUtils.Balances balances;
  uint[] offerOf;

  mapping(uint => mapping(TestUtils.Info => uint)) offers;

  receive() external payable {}

  function saveOffers() internal {
    uint offerId = dex.getBest();
    while (offerId != 0) {
      (uint wants, uint gives, uint nextId, uint gasreq, , , ) = dex
        .getOfferInfo(offerId);
      offers[offerId][TestUtils.Info.makerWants] = wants;
      offers[offerId][TestUtils.Info.makerGives] = gives;
      offers[offerId][TestUtils.Info.gasreq] = gasreq;
      offerId = nextId;
    }
  }

  function saveBalances() internal {
    uint[] memory balA = new uint[](makers.length());
    uint[] memory balB = new uint[](makers.length());
    uint[] memory balWei = new uint[](makers.length());
    for (uint i = 0; i < makers.length(); i++) {
      balA[i] = aToken.balanceOf(address(makers.getMaker(i)));
      balB[i] = bToken.balanceOf(address(makers.getMaker(i)));
      balWei[i] = dex.balanceOf(address(makers.getMaker(i)));
    }
    balances = TestUtils.Balances({
      dexBalanceFees: aToken.balanceOf(address(dex)),
      takerBalanceA: aToken.balanceOf(address(taker)),
      takerBalanceB: bToken.balanceOf(address(taker)),
      takerBalanceWei: dex.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    (aToken, bToken) = DexPre0.setup();

    Test.testNot0x(address(aToken));
    Test.testNot0x(address(bToken));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    dex = DexPre1.setup(aToken, bToken);
    Display.register(address(dex), "dex");
    Test.testNot0x(address(dex));
    dex.setConfigKey(ConfigKey.fee, 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = DexPre2.setup(dex);
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        Display.append("maker-", Display.uint2str(i))
      );
    }
    Display.register(address(makers.getMaker(0)), "failer");
    taker = DexPre3.setup(dex);
    Display.register(address(taker), "taker");
  }

  function d_provisionAll_beforeAll() public {
    // low level tranfer because makers needs gas to transfer to each maker
    (bool success, ) = address(makers).call{gas: gasleft(), value: 80 ether}(
      ""
    ); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");

    for (uint i = 0; i < makers.length(); i++) {
      TestMaker maker = makers.getMaker(i);
      maker.provisionDex(10 ether);
      aToken.mint(address(maker), 5 ether);
      maker.approve(aToken, 5 ether);
    }

    bToken.mint(address(taker), 5 ether);
    taker.approve(bToken, 5 ether);
    taker.approve(aToken, 50 ether);
  }

  // function zeroDust_test() public {
  //   try dex.setConfigKey(ConfigKey.density, 0)  {
  //     testFail("zero density should revert");
  //   } catch Error(
  //     string memory /*reason*/
  //   ) {
  //     testSuccess();
  //   }
  // }

  function a_full_test() public {
    saveBalances();
    offerOf = TestInsert.run(balances, dex, makers, taker, aToken, bToken);
    emit Test.LOG("End of Insert test");
    console.log("End of insert_test, showing OB:");
    Display.printOfferBook(dex);

    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, dex, makers, taker, aToken, bToken);
    emit Test.LOG("End of Snipe test");
    console.log("End of snipe_test, showing OB:");
    Display.printOfferBook(dex);
    Display.logOfferBook(dex, 4);

    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, dex, makers, taker, aToken, bToken);
    emit Test.LOG("End of MarketOrder test");
    console.log("End of marketOrder_test, showing OB:");
    Display.printOfferBook(dex);
    Display.logOfferBook(dex, 4);

    TestCollectFailingOffer.run(
      balances,
      offers,
      dex,
      offerOf[0],
      makers,
      taker,
      aToken,
      bToken
    );
    emit Test.LOG("end of FailingOffer test");
    console.log("End of collectFailingOffer_test, showing OB:");
    Display.printOfferBook(dex);
    Display.logOfferBook(dex, 4);
  }
}
