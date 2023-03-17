// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract Escrow {
    using SafeTransferLib for ERC20;

    ERC20 public constant WBTC =
        ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public constant USDC =
        ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
}
