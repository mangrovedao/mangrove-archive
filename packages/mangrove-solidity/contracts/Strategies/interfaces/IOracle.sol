pragma solidity ^0.7.0;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

interface IOracle {
  function decimals() external view returns (uint8);

  function getPrice(address token) external view returns (uint96);

  function setPrice(address token, uint price) external;
}
