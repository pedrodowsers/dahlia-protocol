// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test, Vm, console } from "@forge-std/Test.sol";
import { PointsFactory } from "@royco/PointsFactory.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { Dahlia } from "src/core/contracts/Dahlia.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { WrappedVaultFactory } from "src/royco/contracts/WrappedVaultFactory.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { ERC20Mock } from "test/common/mocks/ERC20Mock.sol";

contract WrappedVaultRateTest is Test {
    using LibString for uint256;
    using FixedPointMathLib for uint256;
    using DahliaTransUtils for Vm;
    using BoundUtils for Vm;

    TestContext.MarketContext $;
    TestContext.MarketContext $$;
    TestContext ctx;

    PointsFactory pointsFactory = new PointsFactory(POINTS_FACTORY_OWNER);
    WrappedVaultFactory testFactory;
    uint256 constant WAD = 1e18;

    uint256 private constant DEFAULT_REFERRAL_FEE = 0.0e18;
    uint256 private constant DEFAULT_FRONTEND_FEE = 0.0e18;
    uint256 private constant DEFAULT_PROTOCOL_FEE = 0.0e18;

    address private constant DEFAULT_FEE_RECIPIENT = address(0x33f120);

    address public constant POINTS_FACTORY_OWNER = address(0x1);
    address public constant REGULAR_USER = address(0x33f121);
    address public constant REFERRAL_USER = address(0x33f123);

    function setUp() public {
        ctx = new TestContext(vm);
        // change owner of vault to this test
        ctx.setWalletAddress("MARKET_DEPLOYER", address(this));
        // set default fee in dahliaRegistry
        Dahlia dahlia = ctx.createDahlia();
        testFactory = ctx.createRoycoWrappedVaultFactory(dahlia, address(this), DEFAULT_FEE_RECIPIENT, DEFAULT_PROTOCOL_FEE, DEFAULT_FRONTEND_FEE);

        vm.startPrank(ctx.createWallet("OWNER"));
        dahlia.dahliaRegistry().setValue(Constants.VALUE_ID_ROYCO_WRAPPED_VAULT_MIN_INITIAL_FRONTEND_FEE, DEFAULT_FRONTEND_FEE);
        vm.stopPrank();

        $ = ctx.bootstrapMarket("USDC", "WETH", vm.randomLltv(), address(this));
        $$ = ctx.bootstrapMarket("USDE", "WETH", vm.randomLltv(), address(this));

        //testFactory = new WrappedVaultFactory(address(new WrappedVault()), DEFAULT_FEE_RECIPIENT, 0, 0, address(this), address(pointsFactory),
        // address(dahlia));
    }

    function toPercentString(uint256 value, uint256 decimals) public pure returns (string memory) {
        uint256 percent = 10 ** (decimals);
        uint256 integerPart = value * 100 / percent; // Whole number part
        uint256 fractionalValue = value * 100 % percent;
        uint256 divider = percent / 10;
        uint256 fractionalPart = fractionalValue / divider; // Fractional part (1 decimal place)
        string memory integerString = integerPart.toString();
        return fractionalPart == 0 ? integerString : string(abi.encodePacked(integerString, ".", fractionalPart.toString()));
    }

    function printReward(TestContext.MarketContext memory mCtx, string memory message) public view {
        ERC20Mock rewardToken = mCtx.loanToken;
        (,, uint256 rate) = mCtx.vault.rewardToInterval(address(rewardToken));
        uint256 ratePerSec = mCtx.vault.previewRateAfterDeposit(address(rewardToken), 0);
        uint256 decimals = rewardToken.decimals();
        string memory log = string(
            abi.encodePacked(
                message,
                rewardToken.name(),
                ": ratePerSec=",
                ratePerSec.toString(),
                " rate=",
                rate.toString(),
                " percent=",
                toPercentString(ratePerSec * 365 days, 18),
                " decimals=",
                decimals.toString()
            )
        );
        console.log(log);
        uint256 ir = mCtx.dahlia.getMarket(mCtx.marketId).ratePerSec;
        console.log("Dahlia interest ratePerSecond", ir);

        console.log("Dahlia fullUtilizationRate", mCtx.dahlia.getMarket(mCtx.marketId).fullUtilizationRate);
        console.log("Dahlia borrow APR", toPercentString(ir * 365 days, 18));
        uint256 pr = mCtx.dahlia.previewLendRateAfterDeposit(mCtx.marketId, 0);
        console.log("Dahlia lend previewLendRateAfterDeposit:", pr);
        console.log("Dahlia lend APR:", toPercentString(pr * 365 days, 18));
    }

    function prepareRate(TestContext.MarketContext memory mCtx) public {
        // !!!!!! change this params for checking rewards
        uint256 rewardAmount1 = 100_000 * 10 ** mCtx.loanToken.decimals(); // 1000 rewards1
        uint256 depositAmount = 100_000 * 10 ** mCtx.loanToken.decimals();
        uint256 collateralAmount = 1_000_000 * 10 ** mCtx.collateralToken.decimals();
        uint256 borrowAmount = 80_000 * 10 ** mCtx.loanToken.decimals();
        console.log("\nmarketId: ", IDahlia.MarketId.unwrap(mCtx.marketId));

        uint256 price = 1e36; // 1 to 1
        mCtx.oracle.setPrice(price);
        vm.dahliaLendBy(mCtx.carol, depositAmount, mCtx);
        vm.dahliaSupplyCollateralBy(mCtx.alice, collateralAmount, mCtx);

        uint32 start = uint32(block.timestamp);
        uint32 duration = 365 days;

        mCtx.vault.addRewardsToken(address(mCtx.loanToken));

        mCtx.loanToken.mint(address(this), rewardAmount1);
        mCtx.loanToken.approve(address(mCtx.vault), rewardAmount1);
        mCtx.vault.setRewardsInterval(address(mCtx.loanToken), start, start + duration, rewardAmount1, DEFAULT_FEE_RECIPIENT);

        vm.stopPrank();
        vm.forward(1);

        printReward(mCtx, "before borrow - ");

        vm.dahliaBorrowBy(mCtx.alice, borrowAmount, mCtx);
        printReward(mCtx, "after borrow - ");

        vm.stopPrank();
    }

    function testRate() public {
        prepareRate($);
        prepareRate($$);
        uint256 rate1 = $.vault.previewRateAfterDeposit(address($.loanToken), 1);
        uint256 rate2 = $$.vault.previewRateAfterDeposit(address($$.loanToken), 1);
        assertApproxEqAbs(rate1, rate2, 1e8, "rate with decimal 6 and decimal 18 should be almost equal");
    }
}
