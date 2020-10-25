pragma solidity ^0.7.0;

import "./Dex.sol";
import "./TestMaker.sol";
import "./TestToken.sol";
import "./interfaces.sol";
import "@nomiclabs/buidler/console.sol";

contract MakerDeployer {
  address payable[] makers;
  bool deployed;
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
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
        makers[i] = address(new TestMaker(dex));
      }
    }
    deployed = true;
  }

  function provisionForAll(uint amount) external {
    uint k = makers.length;
    console.log("\nProvisioning %d to Dex for makers:\n", amount);
    for (uint i = 0; i < k; i++) {
      console.logAddress(makers[i]);
      TestMaker(makers[i]).provisionDex(amount);
    }
  }
}