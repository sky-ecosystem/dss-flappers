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
import { FarmOwner } from "src/FarmOwner.sol";
import { FlapperDeploy } from "deploy/FlapperDeploy.sol";
import {
    FlapperInit,
    SBEBeamConfig,
    SBEBeamRangeConfig
} from "deploy/FlapperInit.sol";

interface FarmLike {
    function owner() external view returns (address);
    function rewardsDuration() external view returns (uint256);
    function setRewardsDuration(uint256) external;
}

contract SBEBeamTest is DssTest {
    DssInstance dss;
    Splitter    splitter;
    Kicker      kicker;
    FarmLike    farm;
    FarmOwner   farmOwner;
    SBEBeam     beam;

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
        farm       = FarmLike(address(splitter.farm()));

        // Seed values in-range for the ranges configured below and align the
        // farm's rewardsDuration with splitter.hop. Do this while pauseProxy
        // still owns the farm (before initFarmOwner transfers it).
        vm.startPrank(pauseProxy);
        kicker.file("kbump", uint256(5_000e45));
        splitter.file("burn", 0.5e18);
        splitter.file("hop",  1 hours);
        farm.setRewardsDuration(1 hours);
        vm.stopPrank();

        // Deploy the FarmOwner and transfer farm ownership to it.
        farmOwner = FarmOwner(FlapperDeploy.deployFarmOwner({
            deployer: address(this),
            owner:    pauseProxy
        }));

        vm.startPrank(pauseProxy);
        FlapperInit.initFarmOwner(dss, address(farmOwner));
        vm.stopPrank();

        assertEq(farm.owner(), address(farmOwner));

        // Deploy the SBEBeam pointing at the FarmOwner.
        beam = SBEBeam(FlapperDeploy.deploySBEBeam({
            deployer:  address(this),
            owner:     pauseProxy,
            farmOwner: address(farmOwner)
        }));

        address[] memory buds = new address[](1);
        buds[0] = bud;

        vm.startPrank(pauseProxy);
        FlapperInit.initSBEBeam(dss, address(beam), address(farmOwner), SBEBeamConfig({
            ratioStep:   1000_00, // [bps] 1000%, permissive so per-parameter checks drive these tests
            tau:         0,
            kbump:       SBEBeamRangeConfig({min: 1_000e45,  max: 10_000e45, step:  30_00}), // 30%
            burn:        SBEBeamRangeConfig({min: 0,         max: WAD,       step:  80_00}), // 80%
            hop:         SBEBeamRangeConfig({min: 1 minutes, max: 1 days,    step: 200_00}), // 200%
            buds:        buds,
            chainlogKey: "MCD_SBE_BEAM"
        }));
        vm.stopPrank();
    }

    // --- constructor / admin ---

    function testConstructor() public {
        vm.expectEmit();
        emit Rely(address(this));
        SBEBeam b = new SBEBeam(address(kicker), address(farmOwner));

        assertEq(address(b.kicker()),    address(kicker));
        assertEq(address(b.splitter()),  address(splitter));
        assertEq(address(b.farmOwner()), address(farmOwner));
        assertEq(b.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(beam), "SBEBeam");
    }

    function testAuthMethods() public {
        checkModifier(address(beam), "SBEBeam/not-authorized", [
            SBEBeam.kiss.selector,
            SBEBeam.diss.selector,
            bytes4(keccak256("file(bytes32,bytes32,uint256)"))
        ]);
    }

    function testTollMethods() public {
        checkModifier(address(beam), "SBEBeam/not-facilitator", [SBEBeam.set.selector]);
    }

    // --- kiss / diss ---

    function testKissDiss() public {
        address usr = address(0xABCD);
        assertEq(beam.buds(usr), 0);

        vm.expectEmit();
        emit Kiss(usr);
        vm.prank(pauseProxy);
        beam.kiss(usr);
        assertEq(beam.buds(usr), 1);

        vm.expectEmit();
        emit Diss(usr);
        vm.prank(pauseProxy);
        beam.diss(usr);
        assertEq(beam.buds(usr), 0);
    }

    function testFileUint() public {
        checkFileUint(address(beam), "SBEBeam", ["ratioStep", "tau", "toc"]);
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

            vm.expectEmit();
            emit File(id, "min", uint256(42));
            beam.file(id, "min", 42);

            vm.expectEmit();
            emit File(id, "max", uint256(105));
            beam.file(id, "max", 105);

            vm.expectEmit();
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

    // --- set() happy path ---

    function testSet() public {
        uint256 newKbump = 6_000e45;
        uint256 newBurn  = 0.8e18;
        uint256 newHop   = 2 hours;

        vm.expectEmit();
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

        vm.expectEmit();
        emit Set(kbump_, burn_, hop_);
        vm.prank(bud);
        beam.set(kbump_, burn_, hop_);

        assertEq(beam.toc(), block.timestamp);
    }

    function testSetSameHopSkipsRewardsDuration() public {
        // hop is left unchanged, so the farm's reward stream must not be re-rated:
        // neither splitter.file("hop", ...) nor farm.setRewardsDuration(...) should be called.
        uint256 hop_ = splitter.hop();

        vm.expectCall(address(farm), abi.encodeWithSelector(FarmLike.setRewardsDuration.selector), 0);
        vm.prank(bud);
        beam.set(6_000e45, 0.8e18, hop_);

        // kbump and burn are still updated; hop is untouched.
        assertEq(kicker.kbump(),  6_000e45);
        assertEq(splitter.burn(), 0.8e18);
        assertEq(splitter.hop(),  hop_);
    }

    function testSetNewHopCallsRewardsDuration() public {
        // Positive control: when hop changes, setRewardsDuration is forwarded exactly once with the new hop.
        uint256 newHop = 2 hours;

        vm.expectCall(address(farm), abi.encodeWithSelector(FarmLike.setRewardsDuration.selector, newHop), 1);
        vm.prank(bud);
        beam.set(6_000e45, 0.8e18, newHop);

        assertEq(splitter.hop(),         newHop);
        assertEq(farm.rewardsDuration(), newHop);
    }

    // --- set() gating ---

    function testSetModuleHalted() public {
        // Halting the burn engine (Splitter.hop == type(uint256).max) also halts the beam,
        // so a facilitator cannot use set() to revive a governance-stopped engine.
        vm.prank(pauseProxy);
        splitter.file("hop", type(uint256).max);
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

    function testSetBelowMinKbump() public {
        vm.expectRevert("SBEBeam/kbump-below-min");
        vm.prank(bud);
        beam.set(500e45, 0.5e18, 1 hours); // kbump below min (1_000e45)
    }

    function testSetBelowMinBurn() public {
        vm.prank(pauseProxy);
        beam.file("burn", "min", 0.3e18);
        vm.expectRevert("SBEBeam/burn-below-min");
        vm.prank(bud);
        beam.set(5_000e45, 0.1e18, 1 hours); // burn below min (0.3e18)
    }

    function testSetBelowMinHop() public {
        vm.expectRevert("SBEBeam/hop-below-min");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 30 seconds); // hop below min (1 minutes)
    }

    function testSetAboveMaxKbump() public {
        vm.expectRevert("SBEBeam/kbump-above-max");
        vm.prank(bud);
        beam.set(20_000e45, 0.5e18, 1 hours); // kbump above max (10_000e45)
    }

    function testSetAboveMaxBurn() public {
        vm.expectRevert("SBEBeam/burn-above-max");
        vm.prank(bud);
        beam.set(5_000e45, 2e18, 1 hours); // burn above max (WAD)
    }

    function testSetAboveMaxHop() public {
        vm.expectRevert("SBEBeam/hop-above-max");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 2 days); // hop above max (1 days)
    }

    function testSetDeltaAtStepKbump() public {
        vm.prank(pauseProxy);
        beam.file("kbump", "step", 1_00); // 1% of 5_000e45 = 50e45
        vm.prank(bud);
        beam.set(5_050e45, 0.5e18, 1 hours); // delta exactly 50e45 == step
        assertEq(kicker.kbump(), 5_050e45);
    }

    function testSetDeltaAboveStepKbump() public {
        vm.prank(pauseProxy);
        beam.file("kbump", "step", 1_00); // 1% of 5_000e45 = 50e45
        vm.expectRevert("SBEBeam/kbump-delta-above-step");
        vm.prank(bud);
        beam.set(5_050e45 + 1, 0.5e18, 1 hours); // delta 50e45 + 1 > step
    }

    function testSetDeltaAtStepBurn() public {
        vm.prank(pauseProxy);
        beam.file("burn", "step", 10_00); // 10% of 0.5e18 = 0.05e18
        vm.prank(bud);
        beam.set(5_000e45, 0.55e18, 1 hours); // delta exactly 0.05e18 == step
        assertEq(splitter.burn(), 0.55e18);
    }

    function testSetDeltaAboveStepBurn() public {
        vm.prank(pauseProxy);
        beam.file("burn", "step", 10_00); // 10% of 0.5e18 = 0.05e18
        vm.expectRevert("SBEBeam/burn-delta-above-step");
        vm.prank(bud);
        beam.set(5_000e45, 0.55e18 + 1, 1 hours); // delta 0.05e18 + 1 > step
    }

    function testSetDeltaAtStepHop() public {
        vm.prank(pauseProxy);
        beam.file("hop", "step", 30_00); // 30% of 1 hours = 18 minutes
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours + 18 minutes); // delta exactly 18 minutes == step
        assertEq(splitter.hop(),         1 hours + 18 minutes);
        assertEq(farm.rewardsDuration(), 1 hours + 18 minutes);
    }

    function testSetDeltaAboveStepHop() public {
        vm.prank(pauseProxy);
        beam.file("hop", "step", 30_00); // 30% of 1 hours = 18 minutes
        vm.expectRevert("SBEBeam/hop-delta-above-step");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 hours + 18 minutes + 1); // delta 18 minutes + 1 > step
    }

    // --- set() ratio (kbump / hop) check ---

    function testSetRatioDeltaOutsideStep() public {
        // Each parameter stays within its own step, but the combined kbump/hop ratio moves too far.
        vm.prank(pauseProxy);
        beam.file("ratioStep", 17_50); // 17.5% of prevRatio

        // prevRatio = 5_000e45 / 1 hours, newRatio = 6_000e45 / 61 minutes
        // delta ~= 18.0% of prevRatio > ratioStep 17.5%
        vm.expectRevert("SBEBeam/ratio-delta-above-step");
        vm.prank(bud);
        beam.set(6_000e45, 0.5e18, 61 minutes);

        // prevRatio = 5_000e45 / 1 hours, newRatio = 4_000e45 / 59 minutes
        // delta ~= 18.6% of prevRatio > ratioStep 17.5%
        vm.expectRevert("SBEBeam/ratio-delta-above-step");
        vm.prank(bud);
        beam.set(4_000e45, 0.5e18, 59 minutes);
    }

    function testSetRatioDeltaWithinStep() public {
        // Same change as above, but with a ratio step that accommodates it.
        vm.prank(pauseProxy);
        beam.file("ratioStep", 19_00); // 19% of prevRatio

        uint256 snapshotId = vm.snapshot();

        // delta ~= 18.0% of prevRatio <= ratioStep 19%
        vm.prank(bud);
        beam.set(6_000e45, 0.5e18, 61 minutes);
        assertEq(kicker.kbump(), 6_000e45);
        assertEq(splitter.hop(), 61 minutes);

        vm.revertTo(snapshotId);

        // delta ~= 18.6% of prevRatio <= ratioStep 19%
        vm.prank(bud);
        beam.set(4_000e45, 0.5e18, 59 minutes);
        assertEq(kicker.kbump(), 4_000e45);
        assertEq(splitter.hop(), 59 minutes);
    }

    // Simulate state where the current on-chain value is below the newly tightened min.
    // _check should clamp `old` up to min before the delta check, so the operator
    // can still move toward min without tripping step.
    function testSetClampsOldBelowMinKbump() public {
        vm.startPrank(pauseProxy);
        kicker.file("kbump", uint256(500e45));      // below min (1_000e45)
        beam.file("kbump", "step", 10_00);          // 10% of clamped old (1_000e45) = 100e45 == delta
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
        beam.file("burn", "step", 16_67);           // ~16.67% of clamped old (0.3e18) ~= 0.05e18 (>= delta)
        vm.stopPrank();

        // 0.35e18 (new) - clamp(0.1e18, [0.3e18, WAD]) = 0.35e18 - 0.3e18 = 0.05e18, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.35e18, 1 hours);
        assertEq(splitter.burn(), 0.35e18);
    }

    function testSetClampsOldBelowMinHop() public {
        vm.startPrank(pauseProxy);
        splitter.file("hop", 30 seconds);           // below min (1 minutes)
        beam.file("hop", "step", 500_00);           // 500% of clamped old (1 minutes) = 5 minutes == delta
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
        beam.file("kbump", "step", 1_00);           // 1% of clamped old (10_000e45) = 100e45 == delta
        vm.stopPrank();

        // clamp(50_000e45, [..., 10_000e45]) - 9_900e45 (new) = 100e45, OK
        vm.prank(bud);
        beam.set(9_900e45, 0.5e18, 1 hours);
        assertEq(kicker.kbump(), 9_900e45);
    }

    function testSetClampsOldAboveMaxBurn() public {
        vm.startPrank(pauseProxy);
        splitter.file("burn", 2e18);                // above max (WAD)
        beam.file("burn", "step", 5_00);            // 5% of clamped old (WAD) = 0.05e18 == delta
        vm.stopPrank();

        // clamp(2e18, [0, WAD]) - 0.95e18 (new) = 0.05e18, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.95e18, 1 hours);
        assertEq(splitter.burn(), 0.95e18);
    }

    function testSetClampsOldAboveMaxHop() public {
        vm.startPrank(pauseProxy);
        splitter.file("hop", 2 days);               // above max (1 days)
        beam.file("hop", "step", 35);               // 35 bps (~0.35%) of clamped old (1 days) ~= 302 seconds (>= delta 300)
        vm.stopPrank();

        // clamp(2 days, [1 minutes, 1 days]) - (1 days - 5 minutes) (new) = 5 minutes, OK
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 1 days - 5 minutes);
        assertEq(splitter.hop(),         1 days - 5 minutes);
        assertEq(farm.rewardsDuration(), 1 days - 5 minutes);
    }
}
