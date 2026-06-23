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
    SBEBeamConfig
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
        FlapperInit.initFarmOwner(dss, address(farmOwner), "REWARDS_LSSKY_SKY_OWNER");
        vm.stopPrank();

        assertEq(farm.owner(), address(farmOwner));
        assertEq(dss.chainlog.getAddress("REWARDS_LSSKY_SKY_OWNER"), address(farmOwner));

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
            maxKbump:    10_000e45,
            minHop:      5 minutes,
            maxRate:     type(uint256).max, // permissive; rate-specific tests file their own cap
            tau:         0,
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
        assertEq(b.minHop(),             5 minutes);
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
        checkFileUint(address(beam), "SBEBeam", ["maxKbump", "minHop", "maxRate", "tau", "toc"]);
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

    function testFileMinHopTooLow() public {
        // minHop has a hard 5-minute floor that governance itself cannot go below.
        vm.prank(pauseProxy);
        vm.expectRevert("SBEBeam/minHop-too-low");
        beam.file("minHop", 5 minutes - 1 seconds);
    }

    function testFileMinHopAtFloor() public {
        vm.prank(pauseProxy);
        beam.file("minHop", 5 minutes); // exactly at the floor
        assertEq(beam.minHop(), 5 minutes);
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

    // --- set() safety bounds ---

    function testSetAbovemaxKbump() public {
        vm.expectRevert("SBEBeam/kbump-above-max");
        vm.prank(bud);
        beam.set(10_000e45 + 1, 0.5e18, 1 hours); // kbump above max (10_000e45)
    }

    function testSetAtmaxKbump() public {
        vm.prank(bud);
        beam.set(10_000e45, 0.5e18, 1 hours); // kbump exactly at max
        assertEq(kicker.kbump(), 10_000e45);
    }

    function testSetKbumpNotMultipleOfRay() public {
        vm.expectRevert("SBEBeam/kbump-not-multiple-of-RAY");
        vm.prank(bud);
        beam.set(5_000e45 + 1, 0.5e18, 1 hours); // kbump not a whole multiple of RAY
    }

    function testSetBelowMinHop() public {
        vm.expectRevert("SBEBeam/hop-below-min");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 5 minutes - 1 seconds); // hop below min (5 minutes)
    }

    function testSetAtMinHop() public {
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, 5 minutes); // hop exactly at min
        assertEq(splitter.hop(),         5 minutes);
        assertEq(farm.rewardsDuration(), 5 minutes);
    }

    // hop may be raised freely, but it cannot be set to the halt sentinel (type(uint256).max),
    // which is reserved for governance; otherwise a bud could halt and lock itself out (good modifier).
    function testSetHopHaltSentinel() public {
        vm.expectRevert("SBEBeam/hop-halts-engine");
        vm.prank(bud);
        beam.set(5_000e45, 0.5e18, type(uint256).max);
    }

    // The throttling-only directions are never blocked: kbump can be lowered arbitrarily
    // and hop raised arbitrarily, since at worst that stalls the burn stream.
    function testSetKbumpCanGoArbitrarilyLowAndHopCanGoArbitrarilyHigh() public {
        vm.prank(bud);
        beam.set(1e27, 0.5e18, 365 days); // far below the previous kbump (still a RAY multiple), far above the previous hop
        assertEq(kicker.kbump(),         1e27);
        assertEq(splitter.hop(),         365 days);
        assertEq(farm.rewardsDuration(), 365 days);
    }

    function testSetAboveMaxBurn() public {
        vm.expectRevert("SBEBeam/burn-above-max");
        vm.prank(bud);
        beam.set(5_000e45, WAD + 1, 1 hours); // burn above WAD (100%) would revert
    }

    function testSetAtMaxBurn() public {
        vm.prank(bud);
        beam.set(5_000e45, WAD, 1 hours); // burn exactly at WAD (100%)
        assertEq(splitter.burn(), WAD);
    }

    // Lowering burn is always allowed (zero is the safe direction; at worst it stalls the burn stream).
    function testSetBurnCanGoToZero() public {
        vm.prank(bud);
        beam.set(5_000e45, 0, 1 hours);
        assertEq(splitter.burn(), 0);
    }

    // --- set() rate (kbump / hop) check ---

    function testSetRateAboveMax() public {
        // kbump and hop are each within their own bound, but their ratio exceeds maxRate.
        vm.prank(pauseProxy);
        beam.file("maxRate", 1e45); // 3_600e45 / 1 hours

        vm.expectRevert("SBEBeam/rate-above-max");
        vm.prank(bud);
        beam.set(3_600e45, 0.5e18, 1 hours - 1 seconds); // 3_600e45 / 3599 > 1e45 == maxRate
    }

    function testSetRateAtMax() public {
        vm.prank(pauseProxy);
        beam.file("maxRate", 1e45); // 3_600e45 / 1 hours

        vm.prank(bud);
        beam.set(3_600e45, 0.5e18, 1 hours); // 3_600e45 / 3600 = 1e45 == maxRate
        assertEq(kicker.kbump(), 3_600e45);
        assertEq(splitter.hop(), 1 hours);
    }

    // --- deploy/init sanity-check reverts ---

    // FlapperInit's functions are internal (inlined), so route them through these
    // external wrappers; that gives vm.expectRevert a single call frame to match.
    function initFarmOwnerExt(address farmOwner_) external {
        FlapperInit.initFarmOwner(dss, farmOwner_, "FARM_OWNER");
    }

    function initSBEBeamExt(address beam_, address farmOwner_) external {
        address[] memory buds = new address[](1);
        buds[0] = bud;
        FlapperInit.initSBEBeam(dss, beam_, farmOwner_, SBEBeamConfig({
            maxKbump:    10_000e45,
            minHop:      5 minutes,
            maxRate:     type(uint256).max,
            tau:         0,
            buds:        buds,
            chainlogKey: "MCD_SBE_BEAM"
        }));
    }

    function testInitFarmOwnerFarmMismatch() public {
        // A FarmOwner pointing at the wrong farm must be rejected.
        vm.mockCall(
            address(farmOwner),
            abi.encodeWithSignature("farm()"),
            abi.encode(address(0xBAD))
        );

        vm.expectRevert("FarmOwner farm mismatch");
        this.initFarmOwnerExt(address(farmOwner));
    }

    function testInitSBEBeamKickerMismatch() public {
        vm.mockCall(
            address(beam),
            abi.encodeWithSignature("kicker()"),
            abi.encode(address(0xBAD))
        );

        vm.expectRevert("SBEBeam kicker mismatch");
        this.initSBEBeamExt(address(beam), address(farmOwner));
    }

    function testInitSBEBeamSplitterMismatch() public {
        vm.mockCall(
            address(beam),
            abi.encodeWithSignature("splitter()"),
            abi.encode(address(0xBAD))
        );

        vm.expectRevert("SBEBeam splitter mismatch");
        this.initSBEBeamExt(address(beam), address(farmOwner));
    }

    function testInitSBEBeamFarmOwnerMismatch() public {
        vm.expectRevert("SBEBeam farmOwner mismatch");
        this.initSBEBeamExt(address(beam), address(0xBAD));
    }

    function testInitSBEBeamFarmNotOwned() public {
        vm.mockCall(
            address(farm),
            abi.encodeWithSignature("owner()"),
            abi.encode(address(0xBAD))
        );

        vm.expectRevert("SBEBeam farm not owned");
        this.initSBEBeamExt(address(beam), address(farmOwner));
    }
}
