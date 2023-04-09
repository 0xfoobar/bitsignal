// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BitSignal} from "src/BitSignal.sol";

contract BitSignalScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        BitSignal bitsignal = new BitSignal(address(0x1), address(0x2), 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

        vm.stopBroadcast();

    }
}
