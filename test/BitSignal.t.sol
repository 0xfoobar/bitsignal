// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "forge-std/interfaces/IERC20.sol";
import {BitSignal, AggregatorV3Interface} from "../src/BitSignal.sol";
import {MockPriceFeed} from "./MockPriceFeed.sol";

contract BigSignalTest is Test {
    BitSignal public bitsignal;
    MockPriceFeed public mockUsdcPriceFeed;
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // 6 decimals
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant WETH9 = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public balajis = address(0x1);
    address public counterparty = address(0x2);
    address public arbitor = address(0x3);
    address usdcWhale = 0x0A59649758aa4d66E25f08Dd01271e891fe52199; // arbitrary holder addresses chosen to seed our tests
    address wbtcWhale = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address USDC_PRICE_FEED_ADDRESS = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    function setUp() public {
        mockUsdcPriceFeed = new MockPriceFeed();
        vm.prank(arbitor);
        bitsignal = new BitSignal(balajis, counterparty, address(mockUsdcPriceFeed));
    }

    function testSettle() public {
        AggregatorV3Interface btcPriceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // 8 decimals
        uint256 price = bitsignal.chainlinkPrice(btcPriceFeed) / 1e8;
        console2.log(price);
    }

    function testDepositAndInitiateBetAndSettle() public {
        console2.logString('testDepositAndInitiateBetAndSettle beginning...');
        console2.logString('USDC whale balance:');
        uint256 usdsWhaleBalance = USDC.balanceOf(usdcWhale);
        console2.logUint(usdsWhaleBalance);
        console2.log('USDC whale balance: %d', usdsWhaleBalance);
        // Fund balajis and counterparty for test prep
        vm.prank(usdcWhale);
        USDC.transfer(balajis, 1_000_000e6);
        console2.logString('USDC been transferred');
        vm.prank(wbtcWhale);
        WBTC.transfer(counterparty, 1e8);
        console.logString('WBTC been transferred');


        // Now simulate the deposits
        vm.startPrank(balajis);
        USDC.approve(address(bitsignal), type(uint256).max);
        bitsignal.depositUSDC();
        vm.stopPrank();

        vm.startPrank(counterparty);
        WBTC.approve(address(bitsignal), type(uint256).max);
        bitsignal.depositWBTC();
        vm.stopPrank();

        // Prevent settlement before the bet has expired
        vm.startPrank(counterparty);
        vm.expectRevert("bet not finished");
        bitsignal.settle();

        uint256 usdcBeforeSettlement = USDC.balanceOf(counterparty);
        uint256 wbtcBeforeSettlement = WBTC.balanceOf(counterparty);

        // Successfully settle after expiry
        vm.warp(block.timestamp + 100 days);
        bitsignal.settle();

        // Check that winnings received
        assertEq(USDC.balanceOf(counterparty), usdcBeforeSettlement + 1_000_000e6);
        assertEq(WBTC.balanceOf(counterparty), wbtcBeforeSettlement + 1e8);
    }

    function testDepositAndCancelBeforeInitiating() public {
        // Fund balajis and counterparty for test prep
        vm.prank(usdcWhale);
        USDC.transfer(balajis, 1_000_000e6);
        vm.prank(wbtcWhale);
        WBTC.transfer(counterparty, 1e8);

        // Now simulate the deposits
        vm.startPrank(balajis);
        USDC.approve(address(bitsignal), type(uint256).max);
        bitsignal.depositUSDC();

        // Counterparty fails to deposit, so balajis withdraws his collateral risk-free
        uint256 usdcBeforeCancellation = USDC.balanceOf(balajis);
        bitsignal.cancelBeforeInitiation();
        assertEq(USDC.balanceOf(balajis), usdcBeforeCancellation + 1_000_000e6);
        vm.stopPrank();
    }

    function testSwap() public {
      // Fund balajis and counterparty for test prep
      vm.prank(usdcWhale);
      USDC.transfer(balajis, 1_000_000e6);
      vm.prank(wbtcWhale);
      WBTC.transfer(counterparty, 1e8);


      vm.startPrank(balajis);
      USDC.approve(address(bitsignal), type(uint256).max);
      bitsignal.depositUSDC();
      vm.stopPrank();

      vm.startPrank(counterparty);
      WBTC.approve(address(bitsignal), type(uint256).max);
      bitsignal.depositWBTC();
      vm.stopPrank();

      mockUsdcPriceFeed.setAnswer(95000000);
              (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = mockUsdcPriceFeed.latestRoundData();

      console2.log('Decimals: %d', mockUsdcPriceFeed.decimals());
      console2.log('Mocked price: %d', price);
      vm.prank(arbitor);
      uint256 output = bitsignal.swapCollateral(address(USDT), 900_000e6, 500, 3000);

      console2.log("Output: %d", output);
      console2.log("USDC balance after swap: %d", USDC.balanceOf(address(bitsignal)));
      console2.log("USDT balance after swap: %d", USDT.balanceOf(address(bitsignal)));
    }

}
