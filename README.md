# BitSignal

An immutable smart contract that enables Balaji's [1M USDC vs 1 BTC bet](https://twitter.com/balajis/status/1636797265317867520).

Usage is simple:
1. Define two addresses to participate in the bet.
2. Deploy the BitSignal smart contract with those two addresses as constructor arguments. This ensures asset isolation between bets.
3. The counterparties can call `depositUSDC()` and `depositWBTC()` in either order. The second deposit will finalize the bet and start the 90-day timer.
4. When the timer expires, either party can call `settle()`, which queries the Chainlink BTCUSD oracle and sends both assets to the winner.

Contract can be found in `src/BitSignal.sol` and tests in `test/BitSignal.t.sol`.

Enjoy!