// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH_CONTRACT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // 6 decimals
    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // 8 decimals

    AggregatorV3Interface immutable btcPriceFeed;
    AggregatorV3Interface immutable usdcPriceFeed;

    address public immutable balajis;
    address public immutable counterparty;
    address public winner;
    
    bool internal usdcDeposited;
    bool internal wbtcDeposited;
    bool public betInitiated;

    uint256 public startTimestamp;

    address[] STABLECOIN_CONTRACTS = [
      address(USDC), // Circle USDC
      0xdAC17F958D2ee523a2206206994597C13D831ec7, // Tether USDT
      0x4Fabb145d64652a948d72533023f6E7A623C7C53, // Binance BUSD
      0x8E870D67F660D95d5be530380D0eC0bd388289E1, // Paxos USDP
      0x6B175474E89094C44Da98b954EedeAC495271d0F  // DAI stablecoin
    ];

    modifier swapAllowed(address[] calldata hops) {
      // this function will be used only in case of emergency
      // that`s why its better to consume more gas here due to search in array
      // rather than building map in constructor
      require(betInitiated, "bet is not initiated");
      uint256 usdcPrice = chainlinkPrice(usdcPriceFeed);
      require(usdcPrice <= STABLECOIN_MIN_PRICE, "Collateral coin haven`t lost its peg");
      require(hops.length > 1, "Should be at leas one hoop");
      address token = hops[hops.length-1];
      bool found;
      for (uint i=0; i<5; i++) {
        if (STABLECOIN_CONTRACTS[i] == token) {
          found = true;
        }
      }
      require(found, "swap to choosen token is not allowed");
      _;
    }

    constructor(address _balajis, address _counterparty, address _usdcPriceFeedAddress, address _btcPriceFeedAddress) Ownable() {
        balajis = _balajis;
        counterparty = _counterparty;
        usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeedAddress); // 8 decimals
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeedAddress); // 8 decimals
    }

    function _encodePathV3(address[] calldata _hops, uint24[] calldata _fees) internal view returns (bytes memory path) {
        require(_fees.length == _hops.length, "Wrong fees count");
        path = abi.encodePacked(address(USDC));
        for(uint i = 0; i < _hops.length; i++){
            path = abi.encodePacked(path, _fees[i], _hops[i]);
        }
        return path;
    }

    /// @notice Let arbitor to swap collateral in case deposited stablecoin starts to loose it's peg
    function swapCollateral(uint256 amountMinimum, address[] calldata hops, uint24[] calldata fees) external onlyOwner swapAllowed(hops) returns (uint256) {
      ISwapRouter swapRouter = ISwapRouter(UNISWAP_ROUTER);
      TransferHelper.safeApprove(address(USDC), UNISWAP_ROUTER, USDC_AMOUNT);
      ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: _encodePathV3(hops, fees),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: USDC.balanceOf(address(this)),
                amountOutMinimum: amountMinimum
            });
      uint256 output = swapRouter.exactInput(params);
      return output;
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

    /// @notice This will let the winner to take out any token from contract
    function claim(address token) external {
      require(msg.sender == winner, "Imposter!");
      // any contract cound be passed as an input - looks as a security breach
      // but there is no need for safety check - we already checked that sender is a winner and he should be allowed to do whatewer
      SafeERC20.safeTransfer(IERC20(token), winner, IERC20(token).balanceOf(address(this)));
    }

    /// @notice Once 90 days have passed, query Chainlink BTC/USD price feed to determine the winner and send them both collaterals.
    function settle() external {
        require(betInitiated, "bet not initiated");
        require(block.timestamp >= startTimestamp + BET_LENGTH, "bet not finished");

        betInitiated = false;
        
        uint256 wbtcPrice = chainlinkPrice(btcPriceFeed) / 10**btcPriceFeed.decimals();

        if (wbtcPrice >= PRICE_THRESHOLD) {
            winner = balajis;
        } else {
            winner = counterparty;
        }
    }

    /// @notice Fetch the token price with 8 decimals included
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
