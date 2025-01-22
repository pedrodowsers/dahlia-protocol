// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm, console } from "@forge-std/Test.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { TestConstants } from "test/common/TestConstants.sol";
import { TestTypes } from "test/common/TestTypes.sol";

library BoundUtils {
    using MarketMath for uint256;
    using FixedPointMathLib for uint256;
    using LibString for uint256;

    uint256 private constant UINT256_MAX = 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;

    /**
     * Copied from forge StdUtils, because there is only internal visibility;
     */
    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(min <= max, "StdUtils bound(uint256,uint256,uint256): Max is less than min.");
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x >= min && x <= max) {
            return x;
        }

        uint256 size = max - min + 1;

        // If the value is 0, 1, 2, 3, wrap that to min, min+1, min+2, min+3. Similarly for the UINT256_MAX side.
        // This helps ensure coverage of the min/max values.
        if (x <= 3 && size > x) {
            return min + x;
        }
        if (x >= UINT256_MAX - 3 && size > UINT256_MAX - x) {
            return max - (UINT256_MAX - x);
        }

        // Otherwise, wrap x into the range [min, max], i.e. the range is inclusive.
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) {
                return max;
            }
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) {
                return min;
            }
            result = max - rem + 1;
        }
    }

    /**
     * Copied from forge StdUtils, because there is only internal visibility;
     */
    function bound(uint256 x, uint256 min, uint256 max) public pure returns (uint256 result) {
        result = _bound(x, min, max);
        // console2_log_StdUtils("Bound result", result);
    }

    /**
     * Utils
     */
    function marketsEq(Vm, IDahlia.MarketId a, IDahlia.MarketId b) public pure returns (bool) {
        return (IDahlia.MarketId.unwrap(a) == IDahlia.MarketId.unwrap(b));
    }

    function boundBlocks(Vm, uint256 blocks) public pure returns (uint256) {
        return bound(blocks, 1, type(uint32).max);
    }

    function boundAmount(Vm, uint256 amount) public pure returns (uint256) {
        return amount = bound(amount, TestConstants.MIN_TEST_AMOUNT, TestConstants.MAX_TEST_AMOUNT);
    }

    function boundShares(Vm, uint256 amount) public pure returns (uint256) {
        return amount = bound(amount, TestConstants.MIN_TEST_SHARES, TestConstants.MAX_TEST_SHARES);
    }

    function roundLltv(uint256 lltv) public pure returns (uint256) {
        return lltv / 100 * 100;
    }

    function randomLltv(Vm vm) public returns (uint256) {
        return roundLltv(vm.randomUint(TestConstants.MIN_TEST_LLTV, TestConstants.MAX_TEST_LLTV));
    }

    /// @notice get percentage down (x * 100) / %
    function toPercent(uint24 value) internal pure returns (uint24) {
        return uint24(value * Constants.LLTV_100_PERCENT / 100);
    }

    /// @dev Converts a uint256 to a percentage string with 1 decimal place
    /// @notice Used for displaying values as percentages in the UI
    function toPercentString(uint256 value) public pure returns (string memory) {
        uint256 integerPart = value * 100 / Constants.LLTV_100_PERCENT; // Whole number part
        uint256 fractionalValue = value * 100 % Constants.LLTV_100_PERCENT;
        uint256 divider = Constants.LLTV_100_PERCENT / 10;
        uint256 fractionalPart = fractionalValue / divider; // Fractional part (1 decimal place)
        string memory integerString = integerPart.toString();
        return fractionalPart == 0 ? integerString : string(abi.encodePacked(integerString, ".", fractionalPart.toString()));
    }

    function randomLiquidationBonusRate(Vm vm, uint256 lltv) public returns (uint256) {
        return vm.randomUint(1, MarketMath.getMaxLiquidationBonusRate(lltv));
    }

    function generatePositionInLtvRange(Vm vm, TestTypes.MarketPosition memory pos, uint256 minLtv, uint256 maxLtv)
        internal
        pure
        returns (TestTypes.MarketPosition memory)
    {
        pos.ltv = uint24(roundLltv(bound(pos.ltv, minLtv, maxLtv)));
        pos.price = bound(pos.price, TestConstants.MIN_COLLATERAL_PRICE, TestConstants.MAX_COLLATERAL_PRICE);
        pos.borrowed = bound(pos.borrowed, TestConstants.MIN_TEST_AMOUNT, TestConstants.MAX_TEST_AMOUNT);
        pos.collateral = pos.borrowed.divPercentUp(pos.ltv).lendToCollateralUp(pos.price);

        if (pos.collateral > TestConstants.MAX_COLLATERAL_ASSETS) {
            pos.collateral = TestConstants.MAX_COLLATERAL_ASSETS;
            pos.borrowed = FixedPointMathLib.min(pos.collateral.collateralToLendUp(pos.price).mulPercentUp(pos.ltv), TestConstants.MAX_TEST_AMOUNT);
        }

        pos.lent = bound(pos.lent, pos.borrowed + 1, pos.borrowed + TestConstants.MAX_TEST_AMOUNT);

        vm.assume(pos.collateral < type(uint256).max / pos.price);
        logPosition(pos);
        vm.assume(pos.ltv == MarketMath.getLTV(pos.borrowed, pos.collateral, pos.price));
        return pos;
    }

    function forward(Vm vm, uint256 blocks) public {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * TestConstants.BLOCK_TIME); // Block speed should depend on test network.
    }

    function logPosition(TestTypes.MarketPosition memory pos) internal pure {
        console.log("COLLATERAL: ", pos.collateral);
        console.log("COLLATERAL_CAPACITY", pos.borrowed.divPercentUp(pos.ltv));
        console.log("LENT: ", pos.lent);
        console.log("BORROWED: ", pos.borrowed);
        console.log("PRICE: ", pos.price);
        console.log("LTV: ", pos.ltv);
    }
}
