// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IEACAggregatorProxy} from "src/IEACAggregatorProxy.sol";

contract Escrow {
    using SafeTransferLib for ERC20;

    struct Deposits {
        uint128 wbtc;
        uint128 usdc;
    }

    ERC20 public constant WBTC =
        ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
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
    uint256 public constant WBTC_USDC_PRICE = 1_000_000e6;

    // BTC/USD price oracle (Chainlink)
    // https://data.chain.link/ethereum/mainnet/crypto-usd/btc-usd
    // https://etherscan.io/address/0xf4030086522a5beea4988f8ca5b36dbc97bee88c#code
    IEACAggregatorProxy public constant BTC_USD_PRICE_ORACLE =
        IEACAggregatorProxy(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

    // Tracks contract deposits
    Deposits public deposits;

    // Tracks bettors and their betting token and amount
    mapping(address bettor => mapping(ERC20 => uint256 amount)) public bets;
}
