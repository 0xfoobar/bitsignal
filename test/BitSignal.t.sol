// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {BitSignal, ERC20} from "../src/BitSignal.sol";

contract BigSignalTest is Test {
    BitSignal public bitsignal;
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // 6 decimals
    ERC20 constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals
    address public balajis = address(0x1);
    address public counterparty = address(0x2);
    address usdcWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // arbitrary holder addresses chosen to seed our tests
    address wbtcWhale = 0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922;

    function setUp() public {
        bitsignal = new BitSignal(balajis, counterparty);
    }

    function testSettle() public {
        uint256 price = bitsignal.chainlinkPrice() / 1e8;
        console2.log(price);
    }

    function testDepositAndInitiateBetAndSettle() public {
        // Fund balajis and counterparty for test prep
        vm.prank(usdcWhale);
        USDC.transfer(balajis, 1_000_000e6);
        vm.prank(wbtcWhale);
        WBTC.transfer(counterparty, 1e8);

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

}
