// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./Dex.sol";
import "./TestMaker.sol";
import "./TestToken.sol";
import "./interfaces.sol";
import "hardhat/console.sol";
import "./TestFailingMaker.sol";

contract MakerDeployer {
  address payable[] makers;
  TestFailingMaker public failer;
  bool deployed;
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
  }

  receive() external payable {
    uint k = makers.length;
    uint perMaker = msg.value / (k + 1);
    require(perMaker > 0, "0 ether to transfer");
    for (uint i = 0; i < k; i++) {
      address payable maker = makers[i];
      bool ok = maker.send(perMaker);
      require(ok);
    }
    bool ok = address(failer).send(perMaker);
  }

  function length() external view returns (uint) {
    return makers.length;
  }

  function getMaker(uint i) external view returns (TestMaker) {
    return TestMaker(makers[i]);
  }

  function deploy(uint k) external {
    if (!deployed) {
      makers = new address payable[](k);
      for (uint i = 0; i < k; i++) {
        makers[i] = address(new TestMaker(dex));
      }
      failer = new TestFailingMaker(dex);
    }
    deployed = true;
  }
}
