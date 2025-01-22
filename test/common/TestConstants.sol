// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Constants } from "src/core/helpers/Constants.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";

library TestConstants {
    uint256 internal constant BLOCK_TIME = 1;
    uint256 internal constant MAX_COLLATERAL_ASSETS = type(uint128).max;
    uint256 internal constant MIN_COLLATERAL_PRICE = 1e10;
    uint256 internal constant MAX_COLLATERAL_PRICE = 1e26;
    uint256 internal constant MIN_TEST_AMOUNT = 1e5;
    uint256 internal constant MAX_TEST_AMOUNT = 1e32;
    uint256 internal constant MIN_TEST_SHARES = MIN_TEST_AMOUNT * SharesMathLib.SHARES_OFFSET;
    uint256 internal constant MAX_TEST_SHARES = MAX_TEST_AMOUNT * SharesMathLib.SHARES_OFFSET;

    bytes internal constant EMPTY_CALLBACK = bytes("");

    uint256 internal constant MIN_TEST_LLTV = 30 * Constants.LLTV_100_PERCENT / 100;
    uint256 internal constant MAX_TEST_LLTV = 99 * Constants.LLTV_100_PERCENT / 100;
    uint256 internal constant MAX_PERIOD_IN_SECONDS = 100 * 365 days;

    // ROYCO
    uint256 internal constant ROYCO_ERC4626I_FACTORY_PROTOCOL_FEE = 0.01e18;
    uint256 internal constant ROYCO_ERC4626I_FACTORY_MIN_FRONTEND_FEE = 0.02e18;
    uint256 internal constant ROYCO_PROTOCOL_FEE = 0.01e18; // 1% protocol fee
    uint256 internal constant ROYCO_MINIMUM_PROTOCOL_FEE = 0.001e18; // 0.1% minimum frontend fee

    // Timelock
    uint256 internal constant TIMELOCK_DELAY = 3 days;
}
