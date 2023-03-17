// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IEACAggregatorProxy} from "src/IEACAggregatorProxy.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract Escrow {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct Deposits {
        uint256 wbtc;
        uint256 usdc;
    }

    // WBTC: https://etherscan.io/address/0x2260fac5e5542a773aa44fbcfedf7c193bc2c599
    ERC20 public constant WBTC =
        ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    // USDC: https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
    ERC20 public constant USDC =
        ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // 2 WBTC (ERC20 token has 8 decimals, so 2e8 is 2 WBTC)
    uint256 public constant MAX_WBTC = 2e8;

    // 2,000,000 USDC (ERC20 token has 6 decimals, so 2_000_000e6 is 2,000,000 USDC)
    uint256 public constant MAX_USDC = 2_000_000e6;

    /**
     *
     * Bet terms (excerpt from balajis's tweet, see bottom for link)
     *
     * ...
     * Terms of the bet: ideally someone can set up a smart contract where BTC is
     * worth >$1M in 90 days, then I win. If it's worth less than $1M in 90 days,
     * then the counterparty gets the $1M in USD.
     * ...
     *
     * https://twitter.com/balajis/status/1636827051419389952
     *
     * 90 days from the tweet is June 15th, 2023 at 4:29 EST (epoch timestamp below)
     *
     */
    uint256 public immutable END_TIMESTAMP = 1686860940;

    // 8 decimal USD price for 1 (W)BTC (1_000_000e8 is 1,000,000 USD)
    uint256 public constant WBTC_USDC_PRICE = 1_000_000e8;

    // BTC/USD price oracle (Chainlink)
    // https://data.chain.link/ethereum/mainnet/crypto-usd/btc-usd
    // https://etherscan.io/address/0xf4030086522a5beea4988f8ca5b36dbc97bee88c#code
    IEACAggregatorProxy public constant BTC_USD_PRICE_ORACLE =
        IEACAggregatorProxy(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

    // Tracks contract deposits
    Deposits public deposits;

    // Tracks the price of 1 BTC in USD at the end of the bet
    uint256 public btcEndPrice;

    // Tracks bettors and their betting token and amount
    mapping(address bettor => mapping(ERC20 => uint256 amount)) public bets;

    event DepositWBTC(address indexed bettor, uint256 amount);
    event DepositUSDC(address indexed bettor, uint256 amount);
    event SetBTCEndPrice(uint256 price);
    event ClaimUSDC(
        address indexed bettor,
        uint256 betAmount,
        uint256 prizeAmount
    );
    event ClaimWBTC(
        address indexed bettor,
        uint256 betAmount,
        uint256 prizeAmount
    );

    error AmountCannotBeZero();
    error MaxDepositsExceeded();
    error BetHasNotEnded();
    error BetHasEnded();
    error EndPriceAlreadySet();
    error ZeroDepositBalance();

    /**
     * @notice Sets the BTC end price (USD, 8 decimals) after the bet has ended
     */
    function setBTCEndPrice() external {
        // Only allow the end price to be set after the end timestamp
        if (block.timestamp < END_TIMESTAMP) revert BetHasNotEnded();

        // Only allow the end price to be set if it hasn't already been set
        if (btcEndPrice != 0) revert EndPriceAlreadySet();

        // Fetch and set the price from the Chainlink BTC/USD data feed
        (, int256 answer, , , ) = BTC_USD_PRICE_ORACLE.latestRoundData();
        btcEndPrice = uint256(answer);

        emit SetBTCEndPrice(uint256(answer));
    }

    /**
     * @notice Deposit WBTC into the contract
     * @param  amount  uint256  WBTC deposit amount
     */
    function depositWBTC(uint256 amount) external {
        if (amount == 0) revert AmountCannotBeZero();
        if ((deposits.wbtc += amount) > MAX_WBTC) revert MaxDepositsExceeded();

        // If the BTC end price has been set, that means the bet is already over
        if (btcEndPrice != 0) revert BetHasEnded();

        WBTC.safeTransferFrom(msg.sender, address(this), amount);

        bets[msg.sender][WBTC] += amount;

        emit DepositWBTC(msg.sender, amount);
    }

    /**
     * @notice Deposit USDC into the contract
     * @param  amount  uint256  USDC deposit amount
     */
    function depositUSDC(uint256 amount) external {
        if (amount == 0) revert AmountCannotBeZero();
        if ((deposits.usdc += amount) > MAX_USDC) revert MaxDepositsExceeded();

        // If the BTC end price has been set, that means the bet is already over
        if (btcEndPrice != 0) revert BetHasEnded();

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        bets[msg.sender][USDC] += amount;

        emit DepositUSDC(msg.sender, amount);
    }

    /**
     * @notice Allows WBTC depositors to claim their USDC winnings and original bet
     */
    function claimUSDC() external {
        if (btcEndPrice == 0) revert BetHasNotEnded();

        uint256 betAmount = bets[msg.sender][WBTC];

        if (betAmount == 0) revert ZeroDepositBalance();

        // Set the bettors WBTC bet amount to 0 and prevent future claims
        // regardless of whether they won or lost
        bets[msg.sender][WBTC] = 0;

        uint256 prizeAmount;

        // The bettor wins if the BTC price after 90 days is BELOW $1M USD
        if (btcEndPrice < WBTC_USDC_PRICE) {
            // Calculate the bettors share of the USDC winnings based on their WBTC bet amount
            prizeAmount = deposits.usdc.mulDivDown(betAmount, deposits.wbtc);

            // Deduct the claimed USDC winnings from the total USDC deposits
            deposits.usdc -= prizeAmount;

            // Transfer the USDC winnings to the bettor
            USDC.safeTransfer(msg.sender, prizeAmount);

            // Deduct the WBTC bet amount from the total WBTC deposits
            deposits.wbtc -= betAmount;

            // Transfer the WBTC bet amount back to the bettor
            WBTC.safeTransfer(msg.sender, betAmount);
        }

        emit ClaimUSDC(msg.sender, betAmount, prizeAmount);
    }

    /**
     * @notice Allows USDC depositors to claim their WBTC winnings and original bet
     */
    function claimWBTC() external {
        if (btcEndPrice == 0) revert BetHasNotEnded();

        uint256 betAmount = bets[msg.sender][USDC];

        if (betAmount == 0) revert ZeroDepositBalance();

        // Set the bettors USDC bet amount to 0 and prevent future claims
        // regardless of whether they won or lost
        bets[msg.sender][USDC] = 0;

        uint256 prizeAmount;

        // The bettor wins if the BTC price after 90 days is EQUAL TO OR ABOVE $1M USD
        if (btcEndPrice >= WBTC_USDC_PRICE) {
            // Calculate the bettors share of the WBTC winnings based on their USDC bet amount
            prizeAmount = deposits.wbtc.mulDivDown(betAmount, deposits.usdc);

            // Deduct the claimed WBTC winnings from the total WBTC deposits
            deposits.wbtc -= prizeAmount;

            // Transfer the WBTC winnings to the bettor
            WBTC.safeTransfer(msg.sender, prizeAmount);

            // Deduct the USDC bet amount from the total USDC deposits
            deposits.usdc -= betAmount;

            // Transfer the USDC bet amount back to the bettor
            USDC.safeTransfer(msg.sender, betAmount);
        }

        emit ClaimWBTC(msg.sender, betAmount, prizeAmount);
    }
}
