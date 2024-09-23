// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { SplitterInstance } from "deploy/SplitterInstance.sol";
import { FlapperDeploy } from "deploy/FlapperDeploy.sol";
import { SplitterConfig, FlapperUniV2Config, FarmConfig, FlapperInit } from "deploy/FlapperInit.sol";
import { Splitter } from "src/Splitter.sol";
import { FlapperUniV2SwapOnly } from "src/FlapperUniV2SwapOnly.sol";
import { StakingRewardsMock } from "test/mocks/StakingRewardsMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { MedianizerMock } from "test/mocks/MedianizerMock.sol";
import "./helpers/UniswapV2Library.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface VatLike {
    function sin(address) external view returns (uint256);
    function dai(address) external view returns (uint256);
    function can(address, address) external view returns (uint256);
}

interface VowLike {
    function flap() external returns (uint256);
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
    function heal(uint256) external;
    function bump() external view returns (uint256);
    function hump() external view returns (uint256);
}

interface PipLike {
    function read() external view returns (uint256);
    function kiss(address) external;
}

interface EndLike {
    function cage() external;
}

interface SpotterLike {
    function par() external view returns (uint256);
}

interface PairLike {
    function mint(address) external returns (uint256);
    function sync() external;
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
}

contract SplitterTest is DssTest {
    using stdStorage for StdStorage;

    Splitter             public splitter;
    StakingRewardsMock   public farm;
    FlapperUniV2SwapOnly public flapper;
    MedianizerMock       public medianizer;

    address     USDS_JOIN;
    address     SPOT;
    address     USDS;
    address     SKY;
    address     PAUSE_PROXY;

    VatLike     vat;
    VowLike     vow;
    EndLike     end;

    address constant LOG                 = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV2_FACTORY       = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant UNIV2_SKY_USDS_PAIR = 0x2621CC0B3F3c079c1Db0E80794AA24976F0b9e3c;

    event Kick(uint256 tot, uint256 lot, uint256 pay);
    event Cage(uint256 rad);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        USDS_JOIN     = ChainlogLike(LOG).getAddress("USDS_JOIN");
        SPOT          = ChainlogLike(LOG).getAddress("MCD_SPOT");
        USDS          = ChainlogLike(LOG).getAddress("USDS");
        SKY           = ChainlogLike(LOG).getAddress("SKY");
        PAUSE_PROXY   = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        medianizer    = new MedianizerMock();
        vat           = VatLike(ChainlogLike(LOG).getAddress("MCD_VAT"));
        vow           = VowLike(ChainlogLike(LOG).getAddress("MCD_VOW"));
        end           = EndLike(ChainlogLike(LOG).getAddress("MCD_END"));

        vm.startPrank(PAUSE_PROXY);

        medianizer.kiss(address(this));

        farm = new StakingRewardsMock(PAUSE_PROXY, address(0), USDS, address(new GemMock(1_000_000 ether)));

        vm.stopPrank();

        SplitterInstance memory splitterInstance = FlapperDeploy.deploySplitter({
            deployer: address(this),
            owner:    PAUSE_PROXY,
            usdsJoin: USDS_JOIN
        });
        splitter = Splitter(splitterInstance.splitter);

        flapper = FlapperUniV2SwapOnly(FlapperDeploy.deployFlapperUniV2({
            deployer: address(this),
            owner:    PAUSE_PROXY,
            spotter:  SPOT,
            usds:     USDS,
            gem:      SKY,
            pair:     UNIV2_SKY_USDS_PAIR,
            receiver: PAUSE_PROXY,
            swapOnly: true
        }));
        
        // Note - this part emulates the spell initialization
        vm.startPrank(PAUSE_PROXY);
        SplitterConfig memory splitterCfg = SplitterConfig({
            hump:                50_000_000 * RAD,
            bump:                5707 * RAD,
            hop:                 30 minutes,
            burn:                70 * WAD / 100,
            usdsJoin:            USDS_JOIN,
            splitterChainlogKey: "MCD_FLAP_SPLIT",
            prevMomChainlogKey:  "SPLITTER_MOM",
            momChainlogKey:      "SPLITTER_MOM"
        });
        FlapperUniV2Config memory flapperCfg = FlapperUniV2Config({
            want:            WAD * 97 / 100,
            pip:             address(medianizer),
            pair:            UNIV2_SKY_USDS_PAIR,
            usds:            USDS,
            splitter:        address(splitter),
            prevChainlogKey: bytes32(0),
            chainlogKey:     "MCD_FLAP_BURN"
        });
        FarmConfig memory farmCfg = FarmConfig({
            splitter:        address(splitter),
            usdsJoin:        USDS_JOIN,
            hop:             30 minutes,
            prevChainlogKey: bytes32(0),
            chainlogKey:     "MCD_FARM_USDS"
        });

        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        FlapperInit.initSplitter(dss, splitterInstance, splitterCfg);
        FlapperInit.initFlapperUniV2(dss, address(flapper), flapperCfg);
        FlapperInit.initDirectOracle(address(flapper));
        FlapperInit.setFarm(dss, address(farm), farmCfg);
        vm.stopPrank();

        assertEq(dss.chainlog.getAddress("MCD_FLAP_SPLIT"), splitterInstance.splitter);
        assertEq(dss.chainlog.getAddress("MCD_FLAP_BURN"), address(flapper));
        assertEq(dss.chainlog.getAddress("MCD_FARM_USDS"), address(farm));

        // Add initial liquidity if needed
        (uint256 reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, SKY);
        uint256 minimalUsdsReserve = 280_000 * WAD;
        if (reserveUsds < minimalUsdsReserve) {
            medianizer.setPrice(0.06 * 1e18);
            changeUniV2Price(uint256(medianizer.read()), SKY, UNIV2_SKY_USDS_PAIR);
            (reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, SKY);
            if (reserveUsds < minimalUsdsReserve) {
                topUpLiquidity(minimalUsdsReserve - reserveUsds, SKY, UNIV2_SKY_USDS_PAIR);
            }
        } else {
            medianizer.setPrice(uniV2UsdsForGem(WAD, SKY));
        }

        // Create additional surplus if needed
        uint256 bumps = 3 * vow.bump(); // three kicks
        if (vat.dai(address(vow)) < vat.sin(address(vow)) + bumps + vow.hump()) {
            stdstore.target(address(vat)).sig("dai(address)").with_key(address(vow)).depth(0).checked_write(
                vat.sin(address(vow)) + bumps + vow.hump()
            );
        }

        // Heal if needed
        if (vat.sin(address(vow)) > vow.Sin() + vow.Ash()) {
            vow.heal(vat.sin(address(vow)) - vow.Sin() - vow.Ash());
        }
    }

    function refAmountOut(uint256 amountIn, address pip) internal view returns (uint256) {
        return amountIn * WAD / (uint256(PipLike(pip).read()) * RAY / SpotterLike(SPOT).par());
    }

    function uniV2GemForUsds(uint256 amountIn, address gem) internal view returns (uint256 amountOut) {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, gem);
        amountOut = UniswapV2Library.getAmountOut(amountIn, reserveUsds, reserveGem);
    }

    function uniV2UsdsForGem(uint256 amountIn, address gem) internal view returns (uint256 amountOut) {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, gem);
        return UniswapV2Library.getAmountOut(amountIn, reserveGem, reserveUsds);
    }

    function changeUniV2Price(uint256 usdsForGem, address gem, address pair) internal {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, gem);
        uint256 currentUsdsForGem = reserveUsds * WAD / reserveGem;

        // neededReserveUsds * WAD / neededReserveSky = usdsForGem;
        if (currentUsdsForGem > usdsForGem) {
            deal(gem, pair, reserveUsds * WAD / usdsForGem);
        } else {
            deal(USDS, pair, reserveGem * usdsForGem / WAD);
        }
        PairLike(pair).sync();
    }

    function topUpLiquidity(uint256 usdsAmt, address gem, address pair) internal {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, gem);
        uint256 gemAmt = UniswapV2Library.quote(usdsAmt, reserveUsds, reserveGem);

        deal(USDS, address(this), GemLike(USDS).balanceOf(address(this)) + usdsAmt);
        deal(gem, address(this), GemLike(gem).balanceOf(address(this)) + gemAmt);

        GemLike(USDS).transfer(pair, usdsAmt);
        GemLike(gem).transfer(pair, gemAmt);
        uint256 liquidity = PairLike(pair).mint(address(this));
        assertGt(liquidity, 0);
        assertGe(GemLike(pair).balanceOf(address(this)), liquidity);
    }

    function marginalWant(address gem, address pip) internal view returns (uint256) {
        uint256 wbump = vow.bump() / RAY;
        uint256 actual = uniV2GemForUsds(wbump, gem);
        uint256 ref    = refAmountOut(wbump, pip);
        return actual * WAD / ref;
    }

    function doKick() internal {
        uint256 initialVowVatDai = vat.dai(address(vow));
        uint256 initialUsdsJoinVatDai = vat.dai(USDS_JOIN);
        uint256 initialSky = GemLike(SKY).balanceOf(address(PAUSE_PROXY));
        uint256 initialReserveUsds = GemLike(USDS).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialReserveSky = GemLike(SKY).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialFarmUsds = GemLike(USDS).balanceOf(address(farm));
        uint256 prevRewardRate = farm.rewardRate();
        uint256 farmLeftover = block.timestamp >= farm.periodFinish() ? 0 : farm.rewardRate() * (farm.periodFinish() - block.timestamp);
        uint256 farmReward = vow.bump() * (WAD - splitter.burn()) / RAD;
        uint256 prevLastUpdateTime = farm.lastUpdateTime();

        vm.expectEmit(false, false, false, true);
        emit Kick(vow.bump(), vow.bump() * splitter.burn() / RAD, farmReward);
        vow.flap();

        assertEq(vat.dai(address(vow)), initialVowVatDai - vow.bump());
        assertEq(vat.dai(USDS_JOIN), initialUsdsJoinVatDai + vow.bump());
        assertEq(vat.dai(address(splitter)), 0);

        assertEq(GemLike(USDS).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveUsds + vow.bump() * splitter.burn() / RAD);
        if (splitter.burn() == 0) {
            assertEq(GemLike(SKY).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveSky);
            assertEq(GemLike(SKY).balanceOf(address(PAUSE_PROXY)), initialSky);
        } else {
            assertLt(GemLike(SKY).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveSky);
            assertGt(GemLike(SKY).balanceOf(address(PAUSE_PROXY)), initialSky);
        }

        assertEq(GemLike(USDS).balanceOf(address(farm)), initialFarmUsds + farmReward);
        if (splitter.burn() == WAD) {
            assertEq(farm.rewardRate(), prevRewardRate);
            assertEq(farm.lastUpdateTime(), prevLastUpdateTime); 
        } else {
            assertEq(farm.rewardRate(), (farmLeftover + farmReward) / farm.rewardsDuration());
            assertEq(farm.lastUpdateTime(), block.timestamp); 
        }
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        Splitter s = new Splitter(USDS_JOIN);

        assertEq(s.hop(), 1 hours);
        assertEq(s.zzz(), 0);
        assertEq(address(s.usdsJoin()), USDS_JOIN);
        assertEq(address(s.vat()), address(vat));
        assertEq(address(s.farm()), address(0));
        assertEq(s.wards(address(this)), 1);
        assertEq(s.live(), 1);
    }

    function testAuth() public {
        checkAuth(address(splitter), "Splitter");
    }

    function testAuthModifiers() public virtual {
        assert(splitter.wards(address(this)) == 0);

        checkModifier(address(splitter), string(abi.encodePacked("Splitter", "/not-authorized")), [
            Splitter.kick.selector,
            Splitter.cage.selector
        ]);
    }

    function testFileUint() public {
        checkFileUint(address(splitter), "Splitter", ["burn", "hop"]);
    }

    function testFileAddress() public {
        checkFileAddress(address(splitter), "Splitter", ["flapper", "farm"]);
    }

    function testKick() public {
        doKick();
    }

    function testKickBurnOnly() public {
        vm.prank(PAUSE_PROXY); splitter.file("burn", WAD);

        doKick();
    }

    function testKickZeroBurn() public {
        vm.prank(PAUSE_PROXY); splitter.file("burn", 0);

        doKick();
    }

    function testKickAfterHop() public {
        doKick();
        vm.warp(block.timestamp + splitter.hop());

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);
        doKick();
    }

    function testKickBeforeHop() public {
        doKick();
        vm.warp(block.timestamp + splitter.hop() - 1 seconds);

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);
        vm.expectRevert("Splitter/kicked-too-soon");
        vow.flap();
    }

    function testKickAfterStoppedWithHop() public {
        uint256 initialHop = splitter.hop();

        doKick();
        vm.warp(block.timestamp + splitter.hop());

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);

        vm.prank(PAUSE_PROXY); splitter.file("hop", type(uint256).max);
        vm.expectRevert(bytes(abi.encodeWithSignature("Panic(uint256)", 0x11))); // arithmetic error
        vow.flap();

        vm.prank(PAUSE_PROXY); splitter.file("hop", initialHop);
        vow.flap();
    }

    function testKickFlapperNotSet() public {
        vm.prank(PAUSE_PROXY); splitter.file("flapper", address(0));
        vm.expectRevert(bytes("Usds/invalid-address")); // Reverts first as can not mint to address(0) but should also revert on flap.exec
        vow.flap();
    }

    function testKickNotLive() public {
        vm.prank(PAUSE_PROXY); splitter.cage(0);
        assertEq(splitter.live(), 0);
        vm.expectRevert("Splitter/not-live");
        vow.flap();
    }

    function checkChangeRewardDuration(uint256 newDuration) private {
        uint256 topup = 5707 * (WAD - 70 * WAD / 100);
        doKick();
        assertEq(farm.rewardsDuration(), 30 minutes);
        assertEq(farm.rewardRate(), topup / 30 minutes);
        uint256 prevRewardRate = farm.rewardRate();
        vm.warp(block.timestamp + 10 minutes);

        vm.prank(PAUSE_PROXY); farm.setRewardsDuration(newDuration); 
        vm.prank(PAUSE_PROXY); splitter.file("hop", newDuration);

        assertEq(farm.rewardsDuration(), newDuration);
        assertEq(farm.rewardRate(), (prevRewardRate * 20 minutes) / newDuration);
        prevRewardRate = farm.rewardRate();
        assertEq(farm.periodFinish(), block.timestamp + newDuration);

        if (newDuration > 10 minutes) vm.warp(block.timestamp + newDuration - 10 minutes);
        doKick();
        uint256 remaining = newDuration < 10 minutes ? newDuration : 10 minutes;
        assertEq(farm.rewardRate(), (prevRewardRate * remaining + topup) / newDuration);
        assertEq(farm.periodFinish(), block.timestamp + newDuration);

        vm.warp(block.timestamp + newDuration);
        doKick();
        assertEq(farm.rewardRate(), topup / newDuration);
        assertEq(farm.periodFinish(), block.timestamp + newDuration);
    }

    function testIncreaseRewardDuration() public {
        checkChangeRewardDuration(1 hours);
    }

    function testDecreaseRewardDuration() public {
        checkChangeRewardDuration(15 minutes);
    }

    function testDecreaseRewardDurationAllowingImmediateKick() public {
        checkChangeRewardDuration(5 minutes);
    }

    function testCage() public {
        assertEq(splitter.live(), 1);

        vm.expectEmit(false, false, false, true);
        emit Cage(0);
        vm.prank(PAUSE_PROXY); splitter.cage(0);

        assertEq(splitter.live(), 0);
        
        vm.expectRevert("Splitter/not-live");
        vow.flap();
    }

    function testCageThroughEnd() public {
        assertEq(splitter.live(), 1);

        vm.expectEmit(false, false, false, true);
        emit Cage(0);
        vm.prank(PAUSE_PROXY); end.cage();

        assertEq(splitter.live(), 0);

        vm.expectRevert("Splitter/not-live");
        vow.flap();
    }
}
