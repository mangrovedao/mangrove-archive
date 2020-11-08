// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./Test.sol";
import "./DexDeployer.sol";
import "./Dex.sol";
import "./DexCommon.sol";
import "./TestToken.sol";
import "./TestMaker.sol";
import "./MakerDeployer.sol";
import "./TestMoriartyMaker.sol";
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
      initialMinFinishGas: 30000,
      initialPenaltyPerGas: 300,
      initialMinGasWanted: 30000,
      initialMaxGasWanted: 1000000,
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

  function getFee(Dex dex, uint price) internal view returns (uint) {
    return ((price * dex.getConfigUint(ConfigKey.takerFee)) / 10000);
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
  ) public returns (uint) {
    // each maker publishes an order
    makers.getMaker(0).newOrder({
      wants: 1 ether,
      gives: 0.5 ether,
      gasWanted: 3000,
      pivotId: 0
    });
    makers.getMaker(1).newOrder({
      wants: 1 ether,
      gives: 0.8 ether,
      gasWanted: 6000,
      pivotId: 1
    });
    makers.getMaker(2).newOrder({
      wants: 0.5 ether,
      gives: 1 ether,
      gasWanted: 9000,
      pivotId: 72
    });

    //Checking makers have correctly provisoned their offers
    uint minGas = dex.getConfigUint(ConfigKey.minFinishGas);
    for (uint i = 0; i < makers.length(); i++) {
      uint gasWanted_i = (i + 1) * 3000;
      uint provision_i = (gasWanted_i + minGas) *
        dex.getConfigUint(ConfigKey.penaltyPerGas);
      Test.testEq(
        dex.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        Display.append("Incorrect wei balance for maker ", Display.uint2str(i))
      );
    }

    //Checking offers are correctly positioned (2 > 1 > 0)
    uint orderId = dex.best();
    uint expected_maker = 2;
    while (orderId != 0) {
      (, , uint nextId, , , , address makerAddr) = dex.getOrderInfo(orderId);
      Test.testEq(
        makerAddr,
        address(makers.getMaker(expected_maker)),
        Display.append(
          "Incorrect maker address at order ",
          Display.uint2str(orderId)
        )
      );

      expected_maker -= 1;
      orderId = nextId;
    }
  }
}

library TestSnipe {
  uint8 constant _wants = 0;
  uint8 constant _gives = 1;

  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(uint8 => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint orderAmount = 0.3 ether;
    TestMaker maker = makers.getMaker(1); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=dex.getOrderInfo(2);
    uint snipedId = 2;
    //---------------SNIPE------------------//
    taker.take({orderId: snipedId, takerWants: orderAmount});
    Test.testEq(
      aToken.balanceOf(address(dex)),
      balances.dexBalanceFees + TestUtils.getFee(dex, orderAmount),
      "incorrect Dex B balance"
    );
    Test.testEq(
      bToken.balanceOf(address(taker)),
      balances.takerBalanceB -
        (orderAmount * offers[snipedId][_wants]) /
        offers[snipedId][_gives],
      "incorrect taker B balance"
    );
    Test.testEq(
      aToken.balanceOf(address(taker)), // actual
      balances.takerBalanceA + orderAmount - TestUtils.getFee(dex, orderAmount), // expected
      "incorrect taker A balance"
    );
    Test.testEq(
      aToken.balanceOf(address(maker)),
      balances.makersBalanceA[1] - orderAmount,
      "incorrect maker A balance"
    );
    Test.testEq(
      bToken.balanceOf(address(maker)),
      balances.makersBalanceB[1] +
        (orderAmount * offers[snipedId][_wants]) /
        offers[snipedId][_gives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (uint makerWants, uint makerGives, , , , , ) = dex.getOrderInfo(snipedId);
    Test.testEq(
      makerGives,
      offers[snipedId][_gives] - orderAmount,
      "Incorrect residual offer (gives)"
    );
    Test.testEq(
      makerWants,
      (offers[snipedId][_wants] * (offers[snipedId][_gives] - orderAmount)) /
        offers[snipedId][_gives],
      "Incorrect residual offer (wants)"
    );
  }
}

library TestMarketOrder {
  uint8 constant _wants = 0;
  uint8 constant _gives = 1;

  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(uint8 => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    taker.marketOrder(takerWants, takerGives);

    // Checking Makers balances
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(2))),
      balances.makersBalanceA[2] - offers[3][_gives],
      "Incorrect A balance for maker(2)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(2))),
      balances.makersBalanceB[2] + offers[3][_wants],
      "Incorrect B balance for maker(2)"
    );
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceA[1] - offers[2][_gives],
      "Incorrect A balance for maker(1)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + offers[2][_wants],
      "Incorrect B balance for maker(1)"
    );

    uint leftTkrWants = takerWants - (offers[3][_gives] + offers[2][_gives]);
    uint leftMkrWants = (offers[1][_wants] * leftTkrWants) / offers[1][_gives];
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(0))),
      balances.makersBalanceA[0] - leftTkrWants,
      "Incorrect A balance for maker(0)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(0))),
      balances.makersBalanceB[0] + leftMkrWants,
      "Incorrect B balance for maker(0)"
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
        (offers[3][_wants] + offers[2][_wants] + leftMkrWants), // expected
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

library TestInsertCost {
  function deploy(TestMaker maker) public {
    maker.newOrder({
      wants: 1 ether,
      gives: 0.5 ether,
      gasWanted: 3000,
      pivotId: 0
    });
  }

  function run(MakerDeployer makers) internal {
    TestMaker maker = makers.getMaker(0);
    for (uint i = 0; i < 5; i++) {
      Test.testGasCost(
        "newOrder",
        address(TestInsertCost),
        abi.encodeWithSelector(TestInsertCost.deploy.selector, maker)
      );
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
  mapping(uint => mapping(uint8 => uint)) offers;

  receive() external payable {}

  function saveOffers() internal {
    uint orderId = dex.getBest();
    while (orderId != 0) {
      (uint wants, uint gives, uint nextId, , , , ) = dex.getOrderInfo(orderId);
      offers[orderId][0] = wants;
      offers[orderId][1] = gives;
      orderId = nextId;
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

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    dex = DexPre1.setup(aToken, bToken);
    Display.register(address(dex), "dex");
    dex.setConfigKey(ConfigKey.takerFee, 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = DexPre2.setup(dex);
    makers.deploy(3);
    for (uint i = 0; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        Display.append("maker-", Display.uint2str(i))
      );
    }
    taker = DexPre3.setup(dex);
    Display.register(address(taker), "taker");
  }

  function d_provisionAll_beforeAll() public {
    // low level tranfer because makers needs gas to transfer to each maker
    (bool success, ) = address(makers).call{gas: gasleft(), value: 50 ether}(
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
  }

  // function zeroDust_test() public {
  //   try dex.setConfigKey(ConfigKey.dustPerGasWanted, 0)  {
  //     testFail("zero dustPerGastWanted should revert");
  //   } catch Error(
  //     string memory /*reason*/
  //   ) {
  //     testSuccess();
  //   }
  // }

  function a_insert_test() public {
    saveBalances();
    TestInsert.run(balances, dex, makers, taker, aToken, bToken);
    console.log("End of insert_test, showing OB:");
    Display.logOrderBook(dex);
  }

  function b_snipe_test() public {
    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, dex, makers, taker, aToken, bToken);
    console.log("End of snipe_test, showing OB:");
    Display.logOrderBook(dex);
  }

  function c_marketOrder_test() public {
    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, dex, makers, taker, aToken, bToken);
    console.log("End of marketOrder_test, showing OB:");
    Display.logOrderBook(dex);
  }

  function d_insertGasCost_test() public {
    TestInsertCost.run(makers);
    console.log("End of insertGasCost_test, showing OB:");
    Display.logOrderBook(dex);
  }
}
