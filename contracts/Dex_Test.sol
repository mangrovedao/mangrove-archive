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
import "@nomiclabs/buidler/console.sol";
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
    DexDeployer deployer = new DexDeployer(address(this));
    deployer.deploy({
      initialDustPerGasWanted: 100,
      initialMinFinishGas: 30000,
      initialPenaltyPerGas: 300,
      initialMinGasWanted: 30000,
      ofrToken: address(aToken),
      reqToken: address(bToken)
    });
    return deployer.dexes(address(aToken), address(bToken));
  }
}

library DexPre2 {
  function setup(Dex dex) external returns (MakerDeployer) {
    return (new MakerDeployer(dex));
  }
}

library DexPre3 {
  function setup(Dex dex) external returns (TestTaker) {
    return new TestTaker(dex);
  }
}

contract Dex_Test is Test, Display {
  Dex dex;
  TestTaker taker;
  MakerDeployer makers;
  TestToken aToken;
  TestToken bToken;
  uint constant nMakers = 3;

  function deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    (aToken, bToken) = DexPre0.setup();
  }

  function deployDex_beforeAll() public {
    dex = DexPre1.setup(aToken, bToken);
  }

  function deployMakersTaker_beforeAll() public {
    makers = DexPre2.setup(dex);
    makers.deploy(nMakers);
    taker = DexPre3.setup(dex);
  }

  function provisionAll_beforeAll() public {
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

  function zeroDust_test() public {
    try dex.setConfigKey(DC.ConfigKey.dustPerGasWanted, 0)  {
      testFail("zero dustPerGastWanted should revert");
    } catch Error(
      string memory /*reason*/
    ) {
      testSuccess();
    }
  }

  function basicMarketOrder_test() public {
    TestMaker maker2 = makers.getMaker(2);

    makers.getMaker(0).newOrder({
      wants: 1 ether,
      gives: 1 ether,
      gasWanted: 2300,
      pivotId: 0
    });
    uint orderId = maker2.newOrder({
      wants: 1 ether,
      gives: 0.5 ether,
      gasWanted: 8000,
      pivotId: 1
    });

    makers.getMaker(1).newOrder({
      wants: 0.5 ether,
      gives: 1 ether,
      gasWanted: 7000,
      pivotId: 2
    });

    logOrderBook(dex);
    uint orderAmount = 0.3 ether; //of a token
    uint price = 1 ether / 0.5 ether;

    uint init_mkr_a_bal = aToken.balanceOf(address(maker2));
    uint init_mkr_b_bal = bToken.balanceOf(address(maker2));
    uint init_tkr_a_bal = aToken.balanceOf(address(taker));
    uint init_tkr_b_bal = bToken.balanceOf(address(taker));

    taker.take(orderId, orderAmount);
    logOrderBook(dex);

    taker.take({orderId: orderId, takerWants: orderAmount});

    testEq(
      init_mkr_a_bal - orderAmount,
      aToken.balanceOf(address(makers.getMaker(2))),
      "incorrect maker A balance"
    );
    testEq(
      init_mkr_b_bal + orderAmount * price,
      bToken.balanceOf(address(makers.getMaker(2))),
      "incorrect maker B balance"
    );
    testEq(
      init_tkr_a_bal + orderAmount,
      aToken.balanceOf(address(taker)),
      "incorrect taker A balance"
    );
    testEq(
      init_tkr_b_bal - orderAmount * price,
      bToken.balanceOf(address(taker)),
      "incorrect taker B balance"
    );
  }
}
