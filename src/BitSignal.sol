// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "forge-std/console2.sol";

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

contract BitSignal is Ownable {

    uint256 constant BET_LENGTH = 90 days;
    uint256 constant PRICE_THRESHOLD = 1_000_000; // 1 million USD per BTC
    uint256 constant USDC_AMOUNT = 1_000_000e6;
    uint256 constant WBTC_AMOUNT = 1e8;
    uint256 constant STABLECOIN_MIN_PRICE = 97000000; // if price drops below 97 cents consider it as a depeg and permit swap

    address constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IERC20 constant USDC = IERC20(USDC_ADDRESS); // 6 decimals
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals

    AggregatorV3Interface btcPriceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // 8 decimals
    AggregatorV3Interface usdcPriceFeed = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // 8 decimals

    address public immutable balajis;
    address public immutable counterparty;
    
    bool internal usdcDeposited;
    bool internal wbtcDeposited;
    bool public betInitiated;

    uint256 public startTimestamp;

    address[] STABLECOIN_CONTRACTS = [
      USDC_ADDRESS, // Circle USDC
      0xdAC17F958D2ee523a2206206994597C13D831ec7, // Tether USDT
      0x4Fabb145d64652a948d72533023f6E7A623C7C53, // Binance BUSD
      0x8E870D67F660D95d5be530380D0eC0bd388289E1 // Paxos USDP
    ];

    modifier swapAllowed(address token) {
      // this function will be used only in case of emergency
      // that`s why its better to consume more gas here due to search in array
      // rather than building map in constructor
      uint256 usdcPrice = chainlinkPrice(usdcPriceFeed);
      console2.log(usdcPrice);
      require(usdcPrice <= STABLECOIN_MIN_PRICE, "Collateral coin haven`t lost its peg");
      bool found;
      for (uint i=0; i<4; i++) {
        if (STABLECOIN_CONTRACTS[i] == token) {
          found = true;
        }
      }
      require(found, "swap to choosen token is not allowed");
      _;
    }

    constructor(address _balajis, address _counterparty) Ownable() {
        balajis = _balajis;
        counterparty = _counterparty;
    }

    /// @notice Let arbitor to swap collateral in case deposited stablecoin starts to loose it's peg
    function swapCollateral(address token, uint256 amountMinimum, uint24 poolFee) external onlyOwner swapAllowed(token) returns (uint256) {
      ISwapRouter swapRouter = ISwapRouter(UNISWAP_ROUTER);
      TransferHelper.safeApprove(USDC_ADDRESS, UNISWAP_ROUTER, USDC_AMOUNT);
      ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC_ADDRESS,
                tokenOut: token,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: USDC_AMOUNT,
                amountOutMinimum: amountMinimum,
                sqrtPriceLimitX96: 0
            });
      return swapRouter.exactInputSingle(params);
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
        
        uint256 wbtcPrice = chainlinkPrice(btcPriceFeed) / 10**btcPriceFeed.decimals();

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
    function chainlinkPrice(AggregatorV3Interface priceFeed) public view returns (uint256) {
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
