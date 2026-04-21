// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { Splitter }      from "src/Splitter.sol";
import { Kicker }        from "src/Kicker.sol";
import { SBEBeam }       from "src/SBEBeam.sol";
import { StakingRewardsOwner } from "src/StakingRewardsOwner.sol";
import { FlapperDeploy } from "deploy/FlapperDeploy.sol";
import {
    FlapperInit,
    SBEBeamConfig,
    SBEBeamRangeConfig
} from "deploy/FlapperInit.sol";

interface StakingRewardsLike {
    function owner() external view returns (address);
    function rewardsDuration() external view returns (uint256);
    function setRewardsDuration(uint256) external;
}

contract SBEBeamTest is DssTest {
    DssInstance         dss;
    Splitter            splitter;
    Kicker              kicker;
    StakingRewardsLike  farm;
    StakingRewardsOwner stakingRewardsOwner;
    SBEBeam             beam;

    address pauseProxy;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address bud = address(0xB00);

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed id, bytes32 indexed what, uint256 data);
    event Set(uint256 kbump, uint256 burn, uint256 hop);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss        = MCD.loadFromChainlog(LOG);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        splitter   = Splitter(dss.chainlog.getAddress("MCD_SPLIT"));
        kicker     = Kicker(dss.chainlog.getAddress("MCD_KICK"));
        farm       = StakingRewardsLike(address(splitter.farm()));

        // Seed values in-range for the ranges configured below and align the
        // farm's rewardsDuration with splitter.hop. Do this while pauseProxy
        // still owns the farm (before initStakingRewardsOwner transfers it).
        vm.startPrank(pauseProxy);
        kicker.file("kbump", uint256(5_000e45));
        splitter.file("burn", 0.5e18);
        splitter.file("hop",  1 hours);
        farm.setRewardsDuration(1 hours);
        vm.stopPrank();

        // Deploy the StakingRewardsOwner and transfer farm ownership to it.
        stakingRewardsOwner = StakingRewardsOwner(FlapperDeploy.deployStakingRewardsOwner({
            deployer: address(this),
            owner:    pauseProxy
        }));

        vm.startPrank(pauseProxy);
        FlapperInit.initStakingRewardsOwner(dss, address(stakingRewardsOwner));
        vm.stopPrank();

        assertEq(farm.owner(), address(stakingRewardsOwner));

        // Deploy the SBEBeam pointing at the StakingRewardsOwner.
        beam = SBEBeam(FlapperDeploy.deploySBEBeam({
            deployer:            address(this),
            owner:               pauseProxy,
            stakingRewardsOwner: address(stakingRewardsOwner)
        }));

        address[] memory buds = new address[](1);
        buds[0] = bud;

        vm.startPrank(pauseProxy);
        FlapperInit.initSBEBeam(dss, address(beam), address(stakingRewardsOwner), SBEBeamConfig({
            tau:         0,
            kbump:       SBEBeamRangeConfig({min: 1_000e45,  max: 10_000e45, step: 1_000e45}),
            burn:        SBEBeamRangeConfig({min: 0,         max: WAD,       step: WAD}),
            hop:         SBEBeamRangeConfig({min: 1 minutes, max: 1 days,    step: 1 days}),
            buds:        buds,
            chainlogKey: "MCD_SBE_BEAM"
        }));
        vm.stopPrank();
    }

    // --- constructor / admin ---

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        SBEBeam b = new SBEBeam(address(kicker), address(stakingRewardsOwner));

        assertEq(address(b.kicker()),              address(kicker));
        assertEq(address(b.splitter()),            address(splitter));
        assertEq(address(b.stakingRewardsOwner()), address(stakingRewardsOwner));
        assertEq(b.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(beam), "SBEBeam");
    }

    function testAuthMethods() public {
        checkModifier(address(beam), "SBEBeam/not-authorized", [SBEBeam.kiss.selector, SBEBeam.diss.selector]);
    }

    function testTollMethods() public {
        checkModifier(address(beam), "SBEBeam/not-facilitator", [SBEBeam.set.selector]);
    }

    function testFileUint() public {
        checkFileUint(address(beam), "SBEBeam", ["tau", "toc"]);
    }

    function testFileBad() public {
        vm.startPrank(pauseProxy);
        vm.expectEmit(true, false, false, true);
        emit File("bad", uint256(1));
        beam.file("bad", 1);
        assertEq(beam.bad(), 1);

        beam.file("bad", 0);
        assertEq(beam.bad(), 0);
        vm.stopPrank();
    }

    function testFileBadInvalid() public {
        vm.prank(pauseProxy);
        vm.expectRevert("SBEBeam/invalid-bad-value");
        beam.file("bad", 2);
    }

    function testFileTauOverflow() public {
        vm.prank(pauseProxy);
        vm.expectRevert("SBEBeam/invalid-tau-value");
        beam.file("tau", uint256(type(uint64).max) + 1);
    }

    function testFileTocOverflow() public {
        vm.prank(pauseProxy);
        vm.expectRevert("SBEBeam/invalid-toc-value");
        beam.file("toc", uint256(type(uint128).max) + 1);
    }

    function testFileUnrecognizedParam() public {
        vm.prank(pauseProxy);
        vm.expectRevert("SBEBeam/file-unrecognized-param");
        beam.file("unknown", 1);
    }

    // --- file(id, what, data) ---

    function _cfg(bytes32 id) internal view returns (uint256 min_, uint256 max_, uint256 step_) {
        if      (id == "kbump") (min_, max_, step_) = beam.kbumpCfg();
        else if (id == "burn")  (min_, max_, step_) = beam.burnCfg();
        else if (id == "hop")   (min_, max_, step_) = beam.hopCfg();
    }

    function testFileCfg() public {
        vm.startPrank(pauseProxy);
        bytes32[3] memory ids = [bytes32("kbump"), bytes32("burn"), bytes32("hop")];
        for (uint256 i; i < ids.length; i++) {
            bytes32 id = ids[i];

            vm.expectEmit(true, true, false, true);
            emit File(id, "min", uint256(42));
            beam.file(id, "min", 42);

            vm.expectEmit(true, true, false, true);
            emit File(id, "max", uint256(105));
            beam.file(id, "max", 105);

            vm.expectEmit(true, true, false, true);
            emit File(id, "step", uint256(7));
            beam.file(id, "step", 7);

            (uint256 min_, uint256 max_, uint256 step_) = _cfg(id);
            assertEq(min_,  42);
            assertEq(max_,  105);
            assertEq(step_, 7);
        }
        vm.stopPrank();
    }

    function testFileCfgMinTooHigh() public {
        vm.startPrank(pauseProxy);
        beam.file("kbump", "min", 0);
        beam.file("kbump", "max", 100);
        vm.expectRevert("SBEBeam/min-too-high");
        beam.file("kbump", "min", 101);
        vm.stopPrank();
    }

    function testFileCfgMaxTooLow() public {
        vm.startPrank(pauseProxy);
        beam.file("kbump", "min", 0);
        beam.file("kbump", "max", 100);
        beam.file("kbump", "min", 50);
        vm.expectRevert("SBEBeam/max-too-low");
        beam.file("kbump", "max", 49);
        vm.stopPrank();
    }

    function testFileCfgUnrecognizedId() public {
        vm.expectRevert("SBEBeam/file-unrecognized-id");
        vm.prank(pauseProxy);
        beam.file("unknown", "min", 1);
    }

    function testFileCfgUnrecognizedParam() public {
        vm.expectRevert("SBEBeam/file-unrecognized-param");
        vm.prank(pauseProxy);
        beam.file("kbump", "unknown", 1);
    }

    // --- kiss / diss ---

    function testKissDiss() public {
        address usr = address(0xABCD);
        assertEq(beam.buds(usr), 0);

        vm.expectEmit(true, false, false, false);
        emit Kiss(usr);
        vm.prank(pauseProxy);
        beam.kiss(usr);
        assertEq(beam.buds(usr), 1);

        vm.expectEmit(true, false, false, false);
        emit Diss(usr);
        vm.prank(pauseProxy);
        beam.diss(usr);
        assertEq(beam.buds(usr), 0);
    }

    // --- set() happy path ---

    function testSet() public {
        uint256 newKbump = 6_000e45;
        uint256 newBurn  = 0.8e18;
        uint256 newHop   = 2 hours;

        vm.expectEmit(false, false, false, true);
        emit Set(newKbump, newBurn, newHop);
        vm.prank(bud);
        beam.set(newKbump, newBurn, newHop);

        assertEq(kicker.kbump(),         newKbump);
        assertEq(splitter.burn(),        newBurn);
        assertEq(splitter.hop(),         newHop);
        assertEq(farm.rewardsDuration(), newHop);
        assertEq(beam.toc(),             block.timestamp);
    }

    function testSetNoOp() public {
        // Rewriting the same values still emits Set and updates toc.
        uint256 kbump_ = kicker.kbump();
        uint256 burn_  = splitter.burn();
        uint256 hop_   = splitter.hop();

        vm.expectEmit(false, false, false, true);
        emit Set(kbump_, burn_, hop_);
        vm.prank(bud);
        beam.set(kbump_, burn_, hop_);

        assertEq(beam.toc(), block.timestamp);
    }

    // --- set() gating ---

    function testSetModuleHalted() public {
        vm.prank(pauseProxy);
        beam.file("bad", 1);
        vm.expectRevert("SBEBeam/module-halted");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours);
    }

    function testSetTooEarly() public {
        vm.prank(pauseProxy);
        beam.file("tau", 1 hours);

        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours);

        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert("SBEBeam/too-early");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours);

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours);
    }

    // --- set() range checks ---

    function testSetValueNotConfigured() public {
        vm.prank(pauseProxy);
        beam.file("kbump", "step", 0);
        vm.expectRevert("SBEBeam/value-not-configured");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours);
    }

    function testSetBelowMinKbump() public {
        vm.expectRevert("SBEBeam/below-min");
        vm.prank(bud);
        beam.set(500e45, 0.5e18, 1 hours); // kbump below min (1_000e45)
    }

    function testSetBelowMinBurn() public {
        vm.prank(pauseProxy);
        beam.file("burn", "min", 0.3e18);
        vm.expectRevert("SBEBeam/below-min");
        vm.prank(bud);
        beam.set(5_000e45, 0.1e18, 1 hours); // burn below min (0.3e18)
    }

    function testSetBelowMinHop() public {
        vm.expectRevert("SBEBeam/below-min");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 30 seconds); // hop below min (1 minutes)
    }

    function testSetAboveMaxKbump() public {
        vm.expectRevert("SBEBeam/above-max");
        vm.prank(bud);
        beam.set(20_000e45, 0.5e18, 1 hours); // kbump above max (10_000e45)
    }

    function testSetAboveMaxBurn() public {
        vm.expectRevert("SBEBeam/above-max");
        vm.prank(bud);
        beam.set(5_000e45, 2e18, 1 hours); // burn above max (WAD)
    }

    function testSetAboveMaxHop() public {
        vm.expectRevert("SBEBeam/above-max");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 2 days); // hop above max (1 days)
    }

    function testSetDeltaAboveStepKbump() public {
        vm.prank(pauseProxy);
        beam.file("kbump", "step", 100e45);
        vm.expectRevert("SBEBeam/delta-above-step");
        vm.prank(bud);
        beam.set(6_000e45, 0.5e18, 1 hours); // delta 1_000e45 > step 100e45
    }

    function testSetDeltaAboveStepBurn() public {
        vm.prank(pauseProxy);
        beam.file("burn", "step", 0.1e18);
        vm.expectRevert("SBEBeam/delta-above-step");
        vm.prank(bud);
        beam.set(5_000e45, 0.8e18, 1 hours); // delta 0.3e18 > step 0.1e18
    }

    function testSetDeltaAboveStepHop() public {
        vm.prank(pauseProxy);
        beam.file("hop", "step", 30 minutes);
        vm.expectRevert("SBEBeam/delta-above-step");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 2 hours); // delta 1 hours > step 30 minutes
    }

    // Simulate state where the current on-chain value is below the newly tightened min.
    // _check should clamp `old` up to min before the delta check, so the operator
    // can still move toward min without tripping step.
    function testSetClampsOldBelowMinKbump() public {
        vm.startPrank(pauseProxy);
        kicker.file("kbump", uint256(500e45));      // below min (1_000e45)
        beam.file("kbump", "step", 100e45);         // tight step
        vm.stopPrank();

        // 1_100e45 (new) - clamp(500e45, [1_000e45, 10_000e45]) = 1_100e45 - 1_000e45 = 100e45, OK
        vm.prank(bud);
        beam.set(1_100e45, 0.5e18, 1 hours);
        assertEq(kicker.kbump(), 1_100e45);
    }

    function testSetClampsOldBelowMinBurn() public {
        vm.startPrank(pauseProxy);
        splitter.file("burn", 0.1e18);              // below new min (0.3e18)
        beam.file("burn", "min", 0.3e18);
        beam.file("burn", "step", 0.05e18);         // tight step
        vm.stopPrank();

        // 0.35e18 (new) - clamp(0.1e18, [0.3e18, WAD]) = 0.35e18 - 0.3e18 = 0.05e18, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.35e18, 1 hours);
        assertEq(splitter.burn(), 0.35e18);
    }

    function testSetClampsOldBelowMinHop() public {
        vm.startPrank(pauseProxy);
        splitter.file("hop", 30 seconds);           // below min (1 minutes)
        beam.file("hop", "step", 5 minutes);        // tight step
        vm.stopPrank();

        // 6 minutes (new) - clamp(30 seconds, [1 minutes, 1 days]) = 6 minutes - 1 minutes = 5 minutes, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 6 minutes);
        assertEq(splitter.hop(),         6 minutes);
        assertEq(farm.rewardsDuration(), 6 minutes);
    }

    function testSetClampsOldAboveMaxKbump() public {
        vm.startPrank(pauseProxy);
        kicker.file("kbump", uint256(50_000e45));   // above max (10_000e45)
        beam.file("kbump", "step", 100e45);         // tight step
        vm.stopPrank();

        // clamp(50_000e45, [..., 10_000e45]) - 9_900e45 (new) = 100e45, OK
        vm.prank(bud);
        beam.set(9_900e45, 0.5e18, 1 hours);
        assertEq(kicker.kbump(), 9_900e45);
    }

    function testSetClampsOldAboveMaxBurn() public {
        vm.startPrank(pauseProxy);
        splitter.file("burn", 2e18);                // above max (WAD)
        beam.file("burn", "step", 0.05e18);         // tight step
        vm.stopPrank();

        // clamp(2e18, [0, WAD]) - 0.95e18 (new) = 0.05e18, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.95e18, 1 hours);
        assertEq(splitter.burn(), 0.95e18);
    }

    function testSetClampsOldAboveMaxHop() public {
        vm.startPrank(pauseProxy);
        splitter.file("hop", 2 days);               // above max (1 days)
        beam.file("hop", "step", 5 minutes);        // tight step
        vm.stopPrank();

        // clamp(2 days, [1 minutes, 1 days]) - (1 days - 5 minutes) (new) = 5 minutes, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 days - 5 minutes);
        assertEq(splitter.hop(),         1 days - 5 minutes);
        assertEq(farm.rewardsDuration(), 1 days - 5 minutes);
    }
}
