// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from '../src/BitSignal.sol';

contract MockPriceFeed is AggregatorV3Interface {

  int256 internal price;
  uint8 decimalsNumber; 

  constructor(uint8 _decimals) {
    decimalsNumber = _decimals;
  }

  function setAnswer(int256 _answer) external {
    price = _answer;
  }

  function decimals() external view returns (uint8) {
    return decimalsNumber;
  }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
    return (0, price, 0, 0, 0);
  }
}
