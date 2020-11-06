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

library TestInsert {
  function run(
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) public returns (uint) {
    uint[] memory init_mkr_dex_bal = new uint[](makers.length());
    for (uint i = 0; i < makers.length(); i++) {
      init_mkr_dex_bal[i] = dex.balanceOf(address(makers.getMaker(i)));
    }
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
        init_mkr_dex_bal[i] - provision_i,
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
  function run(
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    //logOrderBook(dex);
    uint orderId = 2; // order to snipe (best is 3 (mkr2) > 2 (mkr1) > 1 (mkr0))
    TestMaker maker = makers.getMaker(orderId - 1); // maker whose offer will be sniped

    uint init_mkr_a_bal = aToken.balanceOf(address(maker));
    uint init_mkr_b_bal = bToken.balanceOf(address(maker));
    uint init_tkr_a_bal = aToken.balanceOf(address(taker));
    uint init_tkr_b_bal = bToken.balanceOf(address(taker));
    (uint init_mkrWants, uint init_mkrGives, , , , , ) = dex.getOrderInfo(
      orderId
    );

    {
      uint taken = taker.take({orderId: orderId, takerWants: 0.3 ether});
      //logOrderBook(dex);
      Test.testEq(0.3 ether, taken, "Maker has not delivered expected amount");
    }

    //console.log("Checking taker balance...");
    Test.testEq(
      bToken.balanceOf(address(taker)),
      init_tkr_b_bal - 0.375 ether,
      "incorrect taker B balance"
    );
    Test.testEq(
      aToken.balanceOf(address(taker)), // actual
      init_tkr_a_bal + 0.3 ether, // expected
      "incorrect taker A balance"
    );
    Test.testEq(
      aToken.balanceOf(address(maker)),
      init_mkr_a_bal - 0.3 ether,
      "incorrect maker A balance"
    );
    Test.testEq(
      bToken.balanceOf(address(maker)),
      init_mkr_b_bal + 0.375 ether,
      "incorrect maker B balance"
    );
    // Testing residual offer
    (uint makerWants, uint makerGives, , , , , ) = dex.getOrderInfo(orderId);
    Test.testEq(
      makerGives,
      init_mkrGives - 0.3 ether,
      "Incorrect residual offer"
    );
    Test.testEq(
      makerWants,
      (init_mkrWants * 5) / 8,
      "Incorrect residual offer"
    );
  }
}

library TestMarketOrder {
  function run(
    //    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    uint init_tkr_a_bal = aToken.balanceOf(address(taker));
    uint init_tkr_b_bal = bToken.balanceOf(address(taker));

    uint[] memory init_mkr_a_bal = new uint[](makers.length());
    uint[] memory init_mkr_b_bal = new uint[](makers.length());

    for (uint i = 0; i < makers.length(); i++) {
      init_mkr_a_bal[i] = aToken.balanceOf(address(makers.getMaker(i)));
      init_mkr_b_bal[i] = bToken.balanceOf(address(makers.getMaker(i)));
    }

    taker.marketOrder(takerWants, takerGives);

    // Checking Makers balances
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(2))),
      init_mkr_a_bal[2] - 1 ether,
      "Incorrect A balance for maker(2)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(2))),
      init_mkr_b_bal[2] + 0.5 ether,
      "Incorrect B balance for maker(2)"
    );
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(1))),
      init_mkr_a_bal[1] - 0.5 ether,
      "Incorrect A balance for maker(1)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(1))),
      init_mkr_b_bal[1] + 0.625 ether,
      "Incorrect B balance for maker(1)"
    );
    Test.testEq(
      aToken.balanceOf(address(makers.getMaker(0))),
      init_mkr_a_bal[0] - 0.1 ether,
      "Incorrect A balance for maker(0)"
    );
    Test.testEq(
      bToken.balanceOf(address(makers.getMaker(0))),
      init_mkr_b_bal[0] + 0.2 ether,
      "Incorrect B balance for maker(0)"
    );

    // Checking taker balance
    Test.testEq(
      aToken.balanceOf(address(taker)), // actual
      init_tkr_a_bal + 1.6 ether, // expected
      "incorrect taker A balance"
    );

    Test.testEq(
      bToken.balanceOf(address(taker)), // actual
      init_tkr_b_bal - (0.5 ether + 0.625 ether + 0.2 ether), // expected
      "incorrect taker B balance"
    );
  }
}

contract Dex_Test {
  Dex dex;
  TestTaker taker;
  MakerDeployer makers;
  TestToken aToken;
  TestToken bToken;
  uint constant nMakers = 3;

  receive() external payable {}

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    (aToken, bToken) = DexPre0.setup();

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    // console.log("A token address:");
    // console.logAddress(address(aToken));
    // console.log("B token address:");
    // console.logAddress(address(bToken));
    dex = DexPre1.setup(aToken, bToken);
    Display.register(address(dex), "dex");
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = DexPre2.setup(dex);
    makers.deploy(nMakers);
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
      Display.register(
        address(maker),
        Display.append("maker-", Display.uint2str(i))
      );
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

  function a_test() public {
    TestInsert.run(dex, makers, taker, aToken, bToken);
    console.log("End of insert_test, showing OB:");
    Display.logOrderBook(dex);
  }

  function b_test() public {
    TestSnipe.run(dex, makers, taker, aToken, bToken);
    console.log("End of snipe_test, showing OB:");
    Display.logOrderBook(dex);
  }

  function c_test() public {
    TestMarketOrder.run(makers, taker, aToken, bToken);
    console.log("End of marketOrder_test, showing OB:");
    Display.logOrderBook(dex);
  }
}
