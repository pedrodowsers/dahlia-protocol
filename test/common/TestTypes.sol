// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library TestTypes {
    struct MarketPosition {
        uint256 collateral;
        uint256 lent;
        uint256 borrowed;
        uint256 price;
        uint24 ltv;
    }
}
