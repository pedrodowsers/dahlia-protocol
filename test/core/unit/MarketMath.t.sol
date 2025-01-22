// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { LibString } from "@solady/utils/LibString.sol";
import { Test } from "forge-std/Test.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";

contract MarketMathTest is Test {
    using MarketMath for uint256;
    using SharesMathLib for uint256;
    using LibString for uint256;

    struct MarketData {
        uint256 ta; // total assets
        uint256 ts; // total shares
        uint256 a; // assets
        uint256 s; // shares
        uint256 ra; // expected assets
        uint256 rs; // expected shares
    }

    MarketData[] internal mathSets;

    function processRateTest(function (MarketData memory, string memory) f) internal {
        uint256 length = mathSets.length;
        for (uint256 i = 0; i < length;) {
            f(mathSets[i], i.toString());
            i += 1;
        }
    }

    function test_unit_math_lend() public {
        delete mathSets;
        mathSets.push(MarketData(0, 0, 1, 0, 1, SharesMathLib.SHARES_OFFSET));
        mathSets.push(MarketData(0, 0, 0, SharesMathLib.SHARES_OFFSET, 1, 0));
        mathSets.push(MarketData(100, 100 * SharesMathLib.SHARES_OFFSET, 0, SharesMathLib.SHARES_OFFSET, 1, 0));
        mathSets.push(MarketData(1000, 100 * SharesMathLib.SHARES_OFFSET, 1, 0, 1, 100_899));
        processRateTest(validate_lend);
    }

    function validate_lend(MarketData memory s, string memory index) internal pure {
        uint256 shares = SharesMathLib.toSharesDown(s.a, s.ta, s.ts);
        assertEq(shares, s.rs, index);
    }

    function test_toSharesDown() public pure {
        assertEq(SharesMathLib.toSharesDown(1, 1, 1), 500_000);
        assertEq(SharesMathLib.toSharesDown(1, 1, 0), 500_000);
        assertEq(SharesMathLib.toSharesDown(1, 0, 1), SharesMathLib.SHARES_OFFSET + 1);
        assertEq(SharesMathLib.toSharesDown(1, 0, 0), SharesMathLib.SHARES_OFFSET);
        // accrued interest in total SharesMathLib.SHARES_OFFSET * 2
        assertEq(SharesMathLib.toSharesDown(1, SharesMathLib.SHARES_OFFSET * 2, SharesMathLib.SHARES_OFFSET), 0);
        assertEq(SharesMathLib.toSharesDown(1, SharesMathLib.SHARES_OFFSET, 1), 1);
        assertEq(SharesMathLib.toSharesDown(0, SharesMathLib.SHARES_OFFSET, 1), 0);
    }

    function test_math_getPositionLtv() public pure {
        assertEq(MarketMath.getLTV(2000, 1000, 10e36), 0.2e5); // 20% LTV
        assertEq(MarketMath.getLTV(1000, 2000, 10e36), 0.05e5); // 5% LTV
        assertEq(MarketMath.getLTV(1000, 2000, 1e36), 0.5e5); // 50% LTV
        assertEq(MarketMath.getLTV(2000, 2000, 1e36), 1e5); // 100% LTV
        assertEq(MarketMath.getLTV(4000, 2000, 1e36), 2e5); // 200% LTV
        assertEq(MarketMath.getLTV(4000, 0, 1e36), 0); // 0% LTV if no collateral
        assertEq(MarketMath.getLTV(4000, 2000, 0), 0); // 0% LTV if 0 price
        assertEq(MarketMath.getLTV(0, 2000, 1e36), 0); // 0% LTV if no borrowed assets
    }
}
