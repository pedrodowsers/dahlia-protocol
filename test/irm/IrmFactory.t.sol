// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { console } from "@forge-std/console.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { IrmFactory } from "src/irm/contracts/IrmFactory.sol";
import { IrmFactory } from "src/irm/contracts/IrmFactory.sol";
import { VariableIrm } from "src/irm/contracts/VariableIrm.sol";
import { IrmConstants } from "src/irm/helpers/IrmConstants.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";

contract IrmFactoryTest is Test {
    using BoundUtils for Vm;

    uint64 constant ZERO_UTIL_RATE = 158_247_046;
    uint64 constant MIN_FULL_UTIL_RATE = 1_582_470_460;
    uint64 constant MAX_FULL_UTIL_RATE = 3_164_940_920_000;
    string constant NAME = "Variable IRM_20";

    uint256 ORACLE_PRECISION = 1e18;
    TestContext ctx;
    IrmFactory irmFactory;
    VariableIrm.Config defaultConfig;

    function setUp() public {
        ctx = new TestContext(vm);
        irmFactory = new IrmFactory();

        defaultConfig = VariableIrm.Config({
            minTargetUtilization: 75 * IrmConstants.UTILIZATION_100_PERCENT / 100,
            maxTargetUtilization: 85 * IrmConstants.UTILIZATION_100_PERCENT / 100,
            targetUtilization: 85 * IrmConstants.UTILIZATION_100_PERCENT / 100,
            minFullUtilizationRate: MIN_FULL_UTIL_RATE,
            maxFullUtilizationRate: MAX_FULL_UTIL_RATE,
            zeroUtilizationRate: ZERO_UTIL_RATE,
            rateHalfLife: 172_800,
            targetRatePercent: 0.2e18,
            name: NAME
        });
    }

    function test_irmFactory_variableIrm_success() public {
        vm.pauseGasMetering();
        address expectedIrm = CREATE3.predictDeterministicAddress(keccak256(abi.encode(defaultConfig)), address(irmFactory));

        vm.expectEmit(true, true, true, true, address(expectedIrm));
        emit VariableIrm.VariableIrmConfig(defaultConfig);

        vm.expectEmit(true, true, true, true, address(irmFactory));
        emit IrmFactory.VariableIrmCreated(address(this), address(expectedIrm));
        vm.resumeGasMetering();
        VariableIrm irm = VariableIrm(irmFactory.createVariableIrm(defaultConfig));
        vm.pauseGasMetering();
        assertEq(irm.minFullUtilizationRate(), defaultConfig.minFullUtilizationRate);
        assertEq(irm.zeroUtilizationRate(), defaultConfig.zeroUtilizationRate);
        assertEq(irm.maxFullUtilizationRate(), defaultConfig.maxFullUtilizationRate);
        assertEq(irm.targetRatePercent(), defaultConfig.targetRatePercent);
        assertEq(irm.rateHalfLife(), defaultConfig.rateHalfLife);
        assertEq(irm.targetUtilization(), defaultConfig.targetUtilization);
        assertEq(irm.minTargetUtilization(), defaultConfig.minTargetUtilization);
        assertEq(irm.maxTargetUtilization(), defaultConfig.maxTargetUtilization);

        vm.recordLogs();
        vm.resumeGasMetering();
        VariableIrm irm2 = VariableIrm(irmFactory.createVariableIrm(defaultConfig));
        vm.pauseGasMetering();
        assertEq(address(irm), address(irm2));
        console.log(irm2.name());
        assertEq(NAME, irm2.name());

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Unexpected events were emitted during the creation of irm2");
    }

    function test_irmFactory_variableIrm_reverts() public {
        vm.pauseGasMetering();
        // check minTargetUtilization overflow
        defaultConfig.maxTargetUtilization = IrmConstants.UTILIZATION_100_PERCENT + 1;
        vm.expectRevert(IrmFactory.MaxUtilizationTooHigh.selector);
        vm.resumeGasMetering();
        irmFactory.createVariableIrm(defaultConfig);
        vm.pauseGasMetering();

        // check minTargetUtilization > maxTargetUtilization
        defaultConfig.minTargetUtilization = 76 * IrmConstants.UTILIZATION_100_PERCENT / 100;
        defaultConfig.maxTargetUtilization = 75 * IrmConstants.UTILIZATION_100_PERCENT / 100;
        vm.expectRevert(IrmFactory.MinUtilizationOutOfRange.selector);
        vm.resumeGasMetering();
        irmFactory.createVariableIrm(defaultConfig);
        vm.pauseGasMetering();

        // check maxFullUtilizationRate > maxFullUtilizationRate
        defaultConfig.minTargetUtilization = 70 * IrmConstants.UTILIZATION_100_PERCENT / 100;
        defaultConfig.maxTargetUtilization = 75 * IrmConstants.UTILIZATION_100_PERCENT / 100;
        defaultConfig.minFullUtilizationRate = MAX_FULL_UTIL_RATE;
        defaultConfig.maxFullUtilizationRate = MIN_FULL_UTIL_RATE;
        vm.expectRevert(IrmFactory.FullUtilizationRateRangeInvalid.selector);
        vm.resumeGasMetering();
        irmFactory.createVariableIrm(defaultConfig);
        vm.pauseGasMetering();
    }
}
