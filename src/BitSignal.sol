// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

interface ERC20 {
    function approve(address spender, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external;
    function transferFrom(address sender, address recipient, uint256 amount) external;
    function balanceOf(address holder) external returns (uint256);
}

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

contract BitSignal {

    uint256 constant BET_LENGTH = 90 days;
    uint256 constant PRICE_THRESHOLD = 1_000_000; // 1 million USD per BTC
    uint256 constant USDC_AMOUNT = 1_000_000e6;
    uint256 constant WBTC_AMOUNT = 1e8;

    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // 6 decimals
    ERC20 constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals

    AggregatorV3Interface priceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // 8 decimals

    address public immutable balajis;
    address public immutable counterparty;
    
    bool internal usdcDeposited;
    bool internal wbtcDeposited;
    bool public betInitiated;

    uint256 public startTimestamp;

    constructor(address _balajis, address _counterparty) {
        balajis = _balajis;
        counterparty = _counterparty;
    }

    /// @notice Deposit USDC collateral. This initiates the bet if WBTC already deposited
    function depositUSDC() external {
        require(msg.sender == balajis && !usdcDeposited, "unauthorized");
        USDC.transferFrom(balajis, address(this), USDC_AMOUNT);
        usdcDeposited = true;

        if (wbtcDeposited) {
            betInitiated = true;
            startTimestamp = block.timestamp;
        }
    }

    /// @notice Deposit WBTC collateral. This initiates the bet if USDC already deposited
    function depositWBTC() external {
        require(msg.sender == counterparty && !wbtcDeposited, "unauthorized");
        WBTC.transferFrom(counterparty, address(this), WBTC_AMOUNT);
        wbtcDeposited = true;

        if (usdcDeposited) {
            betInitiated = true;
            startTimestamp = block.timestamp;
        }
    }

    /// @notice Let either counterparty reclaim funds before the bet has been initiated. Useful if the counterparty backs out.
    function cancelBeforeInitiation() external {
        require(msg.sender == balajis || msg.sender == counterparty, "unauthorized");
        require(!betInitiated, "bet already started");

        if (usdcDeposited) {
            usdcDeposited = false;
            USDC.transfer(balajis, USDC.balanceOf(address(this)));
        }
        if (wbtcDeposited) {
            wbtcDeposited = false;
            WBTC.transfer(counterparty, WBTC.balanceOf(address(this)));
        }
    }

    /// @notice Once 90 days have passed, query Chainlink BTC/USD price feed to determine the winner and send them both collaterals.
    function settle() external {
        require(betInitiated, "bet not initiated");
        require(block.timestamp >= startTimestamp + BET_LENGTH, "bet not finished");

        betInitiated = false;
        
        uint256 wbtcPrice = chainlinkPrice() / 10**priceFeed.decimals();

        address winner;
        if (wbtcPrice >= PRICE_THRESHOLD) {
            winner = balajis;
        } else {
            winner = counterparty;
        }

        USDC.transfer(winner, USDC.balanceOf(address(this)));
        WBTC.transfer(winner, WBTC.balanceOf(address(this)));
    }

    /// @notice Fetch the BTCUSD price with 8 decimals included
    function chainlinkPrice() public view returns (uint256) {
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }
}
