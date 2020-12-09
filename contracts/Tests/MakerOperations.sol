// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

contract MakerOperations_Test {
  Dex dex;
  TestMaker mkr;
  TestMaker mkr2;
  TestToken atk;
  TestToken btk;

  receive() external payable {}

  function a_beforeAll() public {
    atk = TokenSetup.setup("A", "$A");
    btk = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(atk, btk);
    mkr = MakerSetup.setup(dex, address(atk), address(btk), false);
    mkr2 = MakerSetup.setup(dex, address(atk), address(btk), false);

    address(mkr).transfer(10 ether);
    address(mkr2).transfer(10 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "MakerOperations_Test");
    Display.register(address(atk), "$A");
    Display.register(address(btk), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
    Display.register(address(mkr2), "maker2");
  }

  function provision_adds_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 235;
    uint amt2 = 1.3 ether;

    mkr.provisionDex(amt1);

    TestEvents.eq(mkr.freeWei(), amt1, "incorrect mkr freeWei amount (1)");
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1,
      "incorrect dex ETH balance (1)"
    );

    mkr.provisionDex(amt2);

    TestEvents.eq(
      mkr.freeWei(),
      amt1 + amt2,
      "incorrect mkr freeWei amount (2)"
    );
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1 + amt2,
      "incorrect dex ETH balance (2)"
    );
  }

  function withdraw_removes_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 0.86 ether;
    uint amt2 = 0.12 ether;

    mkr.provisionDex(amt1);
    bool success = mkr.withdrawDex(amt2);
    TestEvents.check(success, "mkr was not able to withdraw from dex");
    TestEvents.eq(mkr.freeWei(), amt1 - amt2, "incorrect mkr freeWei amount");
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1 - amt2,
      "incorrect dex ETH balance"
    );
  }

  function withdraw_too_much_fails_test() public {
    uint amt1 = 6.003 ether;
    mkr.provisionDex(amt1);
    try mkr.withdrawDex(amt1 + 1) {
      TestEvents.fail("mkr cannot withdraw more than it has");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/insufficientProvision", "wrong revert reason");
    }
  }

  function newOffer_without_freeWei_fails_test() public {
    try mkr.newOffer(1 ether, 1 ether, 0, 0) {
      TestEvents.fail("mkr cannot create offer without provision");
    } catch Error(string memory r) {
      TestEvents.eq(
        r,
        "dex/insufficientProvision",
        "new offer failed for wrong reason"
      );
    }
  }

  function cancel_restores_balance_test() public {
    mkr.provisionDex(1 ether);
    uint bal = mkr.freeWei();
    mkr.cancelOffer(mkr.newOffer(1 ether, 1 ether, 2300, 0));

    TestEvents.eq(mkr.freeWei(), bal, "cancel has not restored balance");
  }

  function cancel_wrong_offer_fails_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.cancelOffer(ofr) {
      TestEvents.fail("mkr2 should not be able to cancel mkr's offer");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/cancelOffer/unauthorized", "wrong revert reason");
    }
  }

  function gasreq_max_with_newOffer_ok_test() public {
    mkr.provisionDex(1 ether);
    uint gasmax = 750000;
    dex.setGasmax(gasmax);
    mkr.newOffer(1 ether, 1 ether, gasmax, 0);
  }

  function gasreq_too_high_fails_newOffer_test() public {
    uint gasmax = 12;
    dex.setGasmax(gasmax);
    try mkr.newOffer(1 ether, 1 ether, gasmax + 1, 0) {
      TestEvents.fail("gasreq above gasmax, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/newOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function min_density_with_newOffer_ok_test() public {
    mkr.provisionDex(1 ether);
    uint density = 10**7;
    dex.setGasbase(1);
    dex.setDensity(address(atk), address(btk), density);
    mkr.newOffer(1 ether, density, 0, 0);
  }

  function low_density_fails_newOffer_test() public {
    uint density = 10**7;
    dex.setGasbase(1);
    dex.setDensity(address(atk), address(btk), density);
    try mkr.newOffer(1 ether, density - 1, 0, 0) {
      TestEvents.fail("density too low, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/newOffer/gives/tooLow", "wrong revert reason");
    }
  }

  function wants_too_wide_fails_newOffer_test() public {
    dex.setGasbase(1);
    dex.setDensity(address(atk), address(btk), 1);
    mkr.provisionDex(1 ether);

    uint wants = type(uint96).max + uint(1);
    try mkr.newOffer(wants, 1, 0, 0) {
      TestEvents.fail("wants wider than 96bits, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/newOffer/wants/96bits", "wrong revert reason");
    }
  }

  function gives_too_wide_fails_newOffer_test() public {
    mkr.provisionDex(1 ether);

    uint gives = type(uint96).max + uint(1);
    try mkr.newOffer(0, gives, 0, 0) {
      TestEvents.fail("gives wider than 96bits, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/newOffer/gives/96bits", "wrong revert reason");
    }
  }

  function pivotId_too_wide_fails_newOffer_test() public {
    dex.setGasbase(1);
    dex.setDensity(address(atk), address(btk), 1);
    mkr.provisionDex(1 ether);

    uint pivotId = type(uint32).max + uint(1);
    try mkr.newOffer(0, 1, 0, pivotId) {
      TestEvents.fail("pivotId wider than 32bits, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/newOffer/pivotId/32bits", "wrong revert reason");
    }
  }
}
