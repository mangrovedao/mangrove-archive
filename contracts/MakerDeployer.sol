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

  function getMaker(uint i) external returns (TestMaker) {
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

  function mintForAll(TestToken t, uint amount) external {
    uint k = makers.length;
    uint perMaker = amount / k;
    require(perMaker > 0);
    console.log("\nMinting %d%s for makers:\n", amount, t.name());
    for (uint i = 0; i < k; i++) {
      console.logAddress(makers[i]);
      TestMaker(makers[i]).provisionDex(amount);
      t.mint(makers[i], perMaker);
      TestMaker(makers[i]).approve(t, amount);
    }
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
