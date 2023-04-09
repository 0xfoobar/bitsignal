// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BitSignal} from "src/BitSignal.sol";

contract BitSignalScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        BitSignal bitsignal = new BitSignal(
          address(0x53Cfaa403a214c9be35011B3Dcfb75D81D2F7B6B),
          address(0x83d47D101881A1E52Ae9C6A2272f499601b8fBCF),
          0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
          0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
        );

        vm.stopBroadcast();

    }
}
