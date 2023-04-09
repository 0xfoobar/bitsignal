// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "forge-std/interfaces/IERC20.sol";
import {BitSignal, AggregatorV3Interface} from "../src/BitSignal.sol";
import {MockPriceFeed} from "./MockPriceFeed.sol";

contract BigSignalTest is Test {
    BitSignal public bitsignal;
    MockPriceFeed public mockUsdcPriceFeed;
    MockPriceFeed public mockBtcPriceFeed;
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // 6 decimals
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant WETH9 = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public balajis = address(0x53Cfaa403a214c9be35011B3Dcfb75D81D2F7B6B);
    address public counterparty = address(0x83d47D101881A1E52Ae9C6A2272f499601b8fBCF);
    address public arbitor = address(0xc37B6361aff0A159Ebc4926285C9DDc8a9D0d1bA);
    address usdcWhale = 0x0A59649758aa4d66E25f08Dd01271e891fe52199; // arbitrary holder addresses chosen to seed our tests
    address wbtcWhale = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address USDC_PRICE_FEED_ADDRESS = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint24[] fees;
    address[] hops;


    function setUp() public {
        mockUsdcPriceFeed = new MockPriceFeed(8);
        mockBtcPriceFeed = new MockPriceFeed(8);
        vm.prank(arbitor);
        fees.push(uint24(500));
        fees.push(uint24(3000));
        hops.push(address(WETH9));
        hops.push(address(USDT));
        bitsignal = new BitSignal(balajis, counterparty, address(mockUsdcPriceFeed), address(mockBtcPriceFeed));
    }

    function testSettle() view public {
        AggregatorV3Interface btcPriceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // 8 decimals
        uint256 price = bitsignal.chainlinkPrice(btcPriceFeed) / 1e8;
        console2.log("BTC price: %s", price);
    }

    function fundParticipantWallets() private {
      uint256 usdcWhaleBalance = USDC.balanceOf(usdcWhale);
      console2.log('USDC whale balance: %d', usdcWhaleBalance);
      uint256 wbtcWhaleBalance = WBTC.balanceOf(wbtcWhale);
      console2.log('WBTC whale balance: %d', wbtcWhaleBalance);
      // Fund balajis and counterparty for test prep
      vm.prank(usdcWhale);
      USDC.transfer(balajis, 1_000_000e6);
      console2.logString('USDC been transferred');
      vm.prank(wbtcWhale);
      WBTC.transfer(counterparty, 1e8);
      console.logString('WBTC been transferred');
    }

    function startBet() private {
      // Now simulate the deposits
      vm.startPrank(balajis);
      USDC.approve(address(bitsignal), type(uint256).max);
      bitsignal.depositUSDC();
      vm.stopPrank();

      vm.startPrank(counterparty);
      WBTC.approve(address(bitsignal), type(uint256).max);
      bitsignal.depositWBTC();
      vm.stopPrank();
    }

    function testDepositAndInitiateBetAndSettleWhenCounterpartyWins() public {
        fundParticipantWallets();
        startBet();
        // Prevent settlement before the bet has expired
        vm.startPrank(counterparty);
        vm.expectRevert("bet not finished");
        bitsignal.settle();

        uint256 usdcBeforeSettlement = USDC.balanceOf(counterparty);
        uint256 wbtcBeforeSettlement = WBTC.balanceOf(counterparty);

        // Successfully settle after expiry
        vm.warp(block.timestamp + 100 days);
        mockBtcPriceFeed.setAnswer(999_999 * 1e8);
        bitsignal.settle();

        // Check that winnings received
        assertEq(USDC.balanceOf(counterparty), usdcBeforeSettlement + 1_000_000e6);
        assertEq(WBTC.balanceOf(counterparty), wbtcBeforeSettlement + 1e8);
    }

    function testDepositAndInitiateBetAndSettleWhenBalajisWins() public {
        fundParticipantWallets();
        startBet();

        uint256 usdcBeforeSettlement = USDC.balanceOf(balajis);
        uint256 wbtcBeforeSettlement = WBTC.balanceOf(balajis);

        // Successfully settle after expiry
        vm.warp(block.timestamp + 100 days);
        mockBtcPriceFeed.setAnswer(1_000_001 * 1e8);
        bitsignal.settle();

        // Check that winnings received
        assertEq(USDC.balanceOf(balajis), usdcBeforeSettlement + 1_000_000e6);
        assertEq(WBTC.balanceOf(balajis), wbtcBeforeSettlement + 1e8);
    }


    function testDepositAndCancelBeforeInitiating() public {
        fundParticipantWallets();

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
      fundParticipantWallets();
      startBet();

      mockUsdcPriceFeed.setAnswer(99000000);

      vm.prank(arbitor);
      vm.expectRevert("Collateral coin haven`t lost its peg");

      bitsignal.swapCollateral(900_000e6, hops, fees);


      mockUsdcPriceFeed.setAnswer(95000000);
      vm.prank(balajis);
      vm.expectRevert("Ownable: caller is not the owner");
      bitsignal.swapCollateral(900_000e6, hops, fees);

      vm.prank(arbitor);
      vm.expectRevert("swap to choosen token is not allowed");
      hops.push(address(WBTC));
      fees.push(3000);
      bitsignal.swapCollateral(900_000e6, hops, fees);
      hops.pop();
      fees.pop();

      vm.prank(arbitor);
      uint256 swapOutput = bitsignal.swapCollateral(900_000e6, hops, fees);

      console2.log("SwapCollateral output: %d", swapOutput);
      console2.log("USDC balance after swap: %d", USDC.balanceOf(address(bitsignal)));
      console2.log("USDT balance after swap: %d", USDT.balanceOf(address(bitsignal)));
      console2.log("balajis address: %s", balajis);
      console2.log("counterparty address: %s", counterparty);
      
      uint256 usdtBeforeSettlement = USDT.balanceOf(counterparty);
      uint256 wbtcBeforeSettlement = WBTC.balanceOf(counterparty);

      // Successfully settle after expiry
      vm.warp(block.timestamp + 100 days);
      mockBtcPriceFeed.setAnswer(999_999 * 1e8);
      bitsignal.settle();

      // Check that winnings received
      assertEq(USDT.balanceOf(counterparty), usdtBeforeSettlement + swapOutput);
      assertEq(WBTC.balanceOf(counterparty), wbtcBeforeSettlement + 1e8);
    }

    function testChangeBeenTransferred() public {
      fundParticipantWallets();
      startBet();
      mockUsdcPriceFeed.setAnswer(95000000);
      vm.prank(arbitor);
      uint256 swapOutput = bitsignal.swapCollateral(900_000e6, hops, fees);
      // simulate change after swap
      uint256 change = 10_000*10**USDC.decimals(); 
      vm.prank(usdcWhale);
      USDC.transfer(address(bitsignal), change);


      uint256 usdtBeforeSettlement = USDT.balanceOf(counterparty);
      uint256 usdcBeforeSettlement = USDC.balanceOf(counterparty);
      uint256 wbtcBeforeSettlement = WBTC.balanceOf(counterparty);

      // Successfully settle after expiry
      vm.warp(block.timestamp + 100 days);
      mockBtcPriceFeed.setAnswer(999_999 * 1e8);
      bitsignal.settle();

      // Check that winnings received
      assertEq(USDT.balanceOf(counterparty), usdtBeforeSettlement + swapOutput);
      assertEq(USDC.balanceOf(counterparty), usdcBeforeSettlement + change);
      assertEq(WBTC.balanceOf(counterparty), wbtcBeforeSettlement + 1e8);

    }

    function testOnRealPriceFeeds() public {
      bitsignal = new BitSignal(
        balajis,
        counterparty,
        address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 
        address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c)
      );

      AggregatorV3Interface btcPriceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // 8 decimals
      AggregatorV3Interface usdcPriceFeed = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // 8 decimals
      uint256 btcPrice = bitsignal.chainlinkPrice(btcPriceFeed) / 1e8;
      uint256 usdcPrice = bitsignal.chainlinkPrice(usdcPriceFeed);
      console2.log("BTC price: %d", btcPrice);
      console2.log("USDC price: %d", usdcPrice);
      fundParticipantWallets();
      startBet();

      // Successfully settle after expiry
      vm.warp(block.timestamp + 100 days);
      bitsignal.settle();

      console2.log("WBTC balance of balajis: %d", WBTC.balanceOf(balajis) / 10**WBTC.decimals());
      console2.log("USDC balance of balajis: %d", USDC.balanceOf(balajis) / 10**USDC.decimals());
      console2.log("WBTC balance of counterparty: %d", WBTC.balanceOf(counterparty) / 10**WBTC.decimals());
      console2.log("USDC balance of counterparty: %d", USDC.balanceOf(counterparty) / 10**USDC.decimals());
    }



}
