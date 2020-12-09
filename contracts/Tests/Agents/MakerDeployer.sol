// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "../../Dex.sol";
import "../../interfaces.sol";
import "./TestMaker.sol";
import "hardhat/console.sol";

//import "./TestMaker.sol";
//import "./TestToken.sol";

contract MakerDeployer {
  address payable[] makers;
  bool deployed;
  Dex dex;
  address atk;
  address btk;

  constructor(
    Dex _dex,
    address _atk,
    address _btk
  ) {
    dex = _dex;
    atk = _atk;
    btk = _btk;
  }

  receive() external payable {
    uint k = makers.length;
    uint perMaker = msg.value / k;
    require(perMaker > 0, "0 ether to transfer");
    for (uint i = 0; i < k; i++) {
      address payable maker = makers[i];
      bool ok = maker.send(perMaker);
      require(ok);
    }
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
        makers[i] = address(new TestMaker(dex, atk, btk, i == 0)); //maker-0 is failer
      }
    }
    deployed = true;
  }
}
