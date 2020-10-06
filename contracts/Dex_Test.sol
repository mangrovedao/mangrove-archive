// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./Test.sol";
import "./DexDeployer.sol";
import "./Dex.sol";
import "./TestToken.sol";
import "./TestMaker.sol";
import "./TestTaker.sol";
import "./interfaces.sol";
import "@nomiclabs/buidler/console.sol";

// Pretest contracts are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md
contract Dex_Test_Pre {
  function setup() public returns (DexDeployer) {
    return (new DexDeployer(msg.sender));
  }
}

contract Dex_Test is Test {
  Dex dex;
  DexDeployer deployer;
  TestMaker maker;
  TestTaker taker;
  TestToken aToken;
  TestToken bToken;

  constructor(Dex_Test_Pre pretest) {
    deployer = pretest.setup();
  }

  function _beforeAll() public {
    aToken = new TestToken(address(this), "A", "$A");
    bToken = new TestToken(address(this), "B", "$B");

    deployer.deploy({
      initialDustPerGasWanted: 100,
      initialMinFinishGas: 30000,
      initialPenaltyPerGas: 300,
      initialMinGasWanted: 30000,
      ofrToken: aToken,
      reqToken: bToken
    });

    dex = deployer.dexes(aToken, bToken);

    maker = new TestMaker(dex);
    taker = new TestTaker(dex);

    address(maker).transfer(100 ether);
    maker.fund(10 ether);
    aToken.mint(address(maker), 5 ether);
    bToken.mint(address(taker), 5 ether);
    maker.approve(aToken, 5 ether);
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

  function basicMarketOrder_test() public {
    uint256 init_mkr_a_bal = aToken.balanceOf(address(maker));
    uint256 init_mkr_b_bal = bToken.balanceOf(address(maker));
    uint256 init_tkr_a_bal = aToken.balanceOf(address(taker));
    uint256 init_tkr_b_bal = bToken.balanceOf(address(taker));

    uint256 orderId = maker.newOrder({
      wants: 1 ether,
      gives: 1 ether,
      gasWanted: 2300,
      pivotId: 0
    });

    uint256 orderAmount = 0.5 ether;

    taker.take({orderId: orderId, wants: orderAmount});

    uint256 expec_mkr_a_bal = init_mkr_a_bal - orderAmount;
    uint256 expec_mkr_b_bal = init_mkr_b_bal + orderAmount;
    uint256 expec_tkr_a_bal = init_tkr_a_bal + orderAmount;
    uint256 expec_tkr_b_bal = init_tkr_b_bal - orderAmount;

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
}
