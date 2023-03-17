// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BitSignal} from "src/BitSignal.sol";

contract BitSignalScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        BitSignal bitsignal = new BitSignal(address(0x1), address(0x2));

        vm.stopBroadcast();

    }
}
