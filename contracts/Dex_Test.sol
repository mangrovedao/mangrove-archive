// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./Test.sol";
import "./DexDeployer.sol";
import "./Dex.sol";
import "./TestToken.sol";
import "./TestMaker.sol";
import "./TestMoriartyMaker.sol";
import "./TestTaker.sol";
import "./interfaces.sol";
import "./Display.sol";
import "@nomiclabs/buidler/console.sol";

// Pretest contracts are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

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
    DexDeployer deployer = new DexDeployer(address(this));
    deployer.deploy({
      initialDustPerGasWanted: 100,
      initialMinFinishGas: 30000,
      initialPenaltyPerGas: 300,
      initialMinGasWanted: 30000,
      ofrToken: aToken,
      reqToken: bToken
    });
    return deployer.dexes(aToken, bToken);
  }
}

library DexPre2 {
  function setup(Dex dex) external returns (TestMaker, TestMoriartyMaker) {
    return (new TestMaker(dex), new TestMoriartyMaker(dex));
  }
}

library DexPre3 {
  function setup(Dex dex) external returns (TestTaker) {
    return new TestTaker(dex);
  }
}

contract Dex_Test is Test {
  Dex dex;
  TestMoriartyMaker evilMaker;
  TestMaker maker;
  TestTaker taker;
  TestToken aToken;
  TestToken bToken;

  function a_beforeAll() public {
    //console.log("IN BEFORE ALL");
    (aToken, bToken) = DexPre0.setup();
  }

  function b_beforeAll() public {
    dex = DexPre1.setup(aToken, bToken);
  }

  function c_beforeAll() public {
    (maker, evilMaker) = DexPre2.setup(dex);
    taker = DexPre3.setup(dex);
    address(maker).transfer(50 ether);
    maker.provisionDex(10 ether);
    address(evilMaker).transfer(50 ether);
    evilMaker.provisionDex(10 ether);

    aToken.mint(address(maker), 5 ether);
    bToken.mint(address(taker), 5 ether);
    maker.approve(aToken, 5 ether);
    evilMaker.approve(aToken, 5 ether);
    taker.approve(bToken, 5 ether);
  }

  // orderList[i] starts with the orderId at position i, followed by order info
  // minus next field.
  struct Spec {
    uint orderId;
    uint wants;
    uint gives;
    uint gasWanted;
    uint minFinishGas;
    uint penaltyPerGas;
    address maker;
  }

  function specOf(
    uint orderId,
    uint wants,
    uint gives,
    uint gasWanted,
    uint minFinishGas,
    uint penaltyPerGas,
    address maker
  ) internal pure returns (Spec memory spec) {
    return
      Spec({
        orderId: orderId,
        wants: wants,
        gives: gives,
        gasWanted: gasWanted,
        minFinishGas: minFinishGas,
        penaltyPerGas: penaltyPerGas,
        maker: maker
      });
  }

  function testDex(Spec[] memory orderList) internal {
    uint orderId = dex.best();
    for (uint i = 0; i < orderList.length; i++) {
      (
        uint wants,
        uint gives,
        uint nextId,
        uint gasWanted,
        uint minFinishGas, // global minFinishGas at order creation time
        uint penaltyPerGas, // global penaltyPerGas at order creation time
        address maker
      ) = dex.getOrderInfo(orderId);
      Spec memory spec = orderList[i];
      testEq(spec.orderId, orderId, "incorrect order Id");
      testEq(spec.wants, wants, "incorrect wanted price");
      testEq(spec.gives, gives, "incorrect give price");
      testEq(spec.gasWanted, gasWanted, "incorrect gas wanted");
      testEq(spec.minFinishGas, minFinishGas, "incorrect min finish gas");
      testEq(spec.penaltyPerGas, penaltyPerGas, "incorrect penalty");
      testEq(spec.maker, maker, "incorrect maker address");
      orderId = nextId;
    }
  }

  function _beforeAll() public {
    address(maker).transfer(100 ether);
    maker.provisionDex(10 ether);
    address(evilMaker).transfer(100 ether);
    evilMaker.provisionDex(10 ether);
    aToken.mint(address(maker), 5 ether);
    aToken.mint(address(evilMaker), 5 ether);
    bToken.mint(address(taker), 5 ether);
    maker.approve(aToken, 5 ether);
    evilMaker.approve(aToken, 5 ether);
    taker.approve(bToken, 5 ether);
  }

  function zeroDust_test() public {
    try dex.updateDustPerGasWanted(0)  {
      testFail("zero dustPerGastWanted should revert");
    } catch Error(
      string memory /*reason*/
    ) {
      testSuccess();
    }
  }

  function newOrder(
    TestMaker maker,
    uint wants,
    uint gives,
    uint gasWanted,
    uint pivotId
  ) internal returns (Spec memory, uint) {
    uint orderId = maker.newOrder({
      wants: 1 ether,
      gives: 1 ether,
      gasWanted: 2300,
      pivotId: 0
    });
    Spec memory spec = specOf({
      orderId: orderId,
      wants: 1 ether,
      gives: 1 ether,
      gasWanted: 2300,
      minFinishGas: dex.minFinishGas(),
      penaltyPerGas: dex.penaltyPerGas(),
      maker: address(maker)
    });
    return (spec, orderId);
  }

  function basicMarketOrder_test() public {
    uint init_mkr_a_bal = aToken.balanceOf(address(maker));
    uint init_mkr_b_bal = bToken.balanceOf(address(maker));
    uint init_tkr_a_bal = aToken.balanceOf(address(taker));
    uint init_tkr_b_bal = bToken.balanceOf(address(taker));
    (Spec memory spec0, uint orderId0) = newOrder({
      maker: maker,
      wants: 1 ether,
      gives: 1 ether,
      gasWanted: 2300,
      pivotId: 0
    });
    (Spec memory spec1, uint orderId1) = newOrder({
      maker: maker,
      wants: 1 ether,
      gives: 0.5 ether,
      gasWanted: 2800,
      pivotId: 0
    });

    Spec[] memory specOB = new Spec[](2);
    specOB[0] = spec0; // best offer
    specOB[1] = spec1;

    // Testing correct insertion in OB
    testDex(specOB);

    uint orderAmount = 0.5 ether;

    taker.take({orderId: orderId1, wants: orderAmount});

    uint expec_mkr_a_bal = init_mkr_a_bal - orderAmount;
    uint expec_mkr_b_bal = init_mkr_b_bal + orderAmount;
    uint expec_tkr_a_bal = init_tkr_a_bal + orderAmount;
    uint expec_tkr_b_bal = init_tkr_b_bal - orderAmount;

    testEq(
      expec_mkr_a_bal,
      aToken.balanceOf(address(maker)),
      "incorrect maker A balance"
    );
    testEq(
      expec_mkr_b_bal,
      bToken.balanceOf(address(maker)),
      "incorrect maker B balance"
    );
    testEq(
      expec_tkr_a_bal,
      aToken.balanceOf(address(taker)),
      "incorrect taker A balance"
    );
    testEq(
      expec_tkr_b_bal,
      bToken.balanceOf(address(taker)),
      "incorrect taker B balance"
    );
  }

  // function moriartyMaketOrder_test() public {
  //   // Maker adds dummy order
  //   maker.newOrder({
  //     wants: 1 ether,
  //     gives: 1 ether,
  //     gasWanted: 2300,
  //     pivotId: 0
  //   });
  //
  //   uint orderAmount = 0.5 ether;
  //   try taker.mo({wants: orderAmount, gives: orderAmount})  {
  //     testFail("taking moriarty offer should fail");
  //   } catch Error(
  //     string memory /*reason*/
  //   ) {
  //     testSuccess();
  //   }
  // }
}
