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

import { FlapperDeploy } from "deploy/FlapperDeploy.sol";
import { KickerConfig, FlapperInit } from "deploy/FlapperInit.sol";
import { Splitter } from "src/Splitter.sol";
import { Kicker } from "src/Kicker.sol";
import { FlapperUniV2SwapOnly } from "src/FlapperUniV2SwapOnly.sol";
import { StakingRewardsMock } from "test/mocks/StakingRewardsMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import "./helpers/UniswapV2Library.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface VatLike {
    function wards(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function dai(address) external view returns (uint256);
    function can(address, address) external view returns (uint256);
}

interface VowLike {
    function bump() external view returns (uint256);
    function hump() external view returns (uint256);
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
    function heal(uint256) external;
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

interface MedianizerLike {
    function read() external view returns (uint256);
}

interface StakingRewardsLike {
    function rewardRate() external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function rewardsDuration() external view returns (uint256);
}

interface FileLike2 is FileLike {
    function file(bytes32, int256) external;
}

contract KickerTest is DssTest {
    using stdStorage for StdStorage;

    Splitter             public splitter;
    StakingRewardsLike   public farm;
    FlapperUniV2SwapOnly public flapper;
    Kicker               public kicker;
    MedianizerLike       public medianizer;
    address              public PAUSE_PROXY;
    address              public USDS;
    address              public SKY;
    address              public USDS_JOIN;
    address              public SPOT;

    VatLike     vat;
    VowLike     vow;

    address constant LOG                 = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV2_FACTORY       = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant UNIV2_SKY_USDS_PAIR = 0x2621CC0B3F3c079c1Db0E80794AA24976F0b9e3c;

    event Kick(uint256 tot, uint256 lot, uint256 pay);
    event Cage(uint256 rad);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        PAUSE_PROXY = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        USDS = ChainlogLike(LOG).getAddress("USDS");
        SKY = ChainlogLike(LOG).getAddress("SKY");
        USDS_JOIN = ChainlogLike(LOG).getAddress("USDS_JOIN");
        SPOT = ChainlogLike(LOG).getAddress("MCD_SPOT");
        splitter = Splitter(ChainlogLike(LOG).getAddress("MCD_SPLIT"));
        flapper = FlapperUniV2SwapOnly(ChainlogLike(LOG).getAddress("MCD_FLAP"));
        medianizer = MedianizerLike(ChainlogLike(LOG).getAddress("FLAP_SKY_ORACLE"));
        vat = VatLike(ChainlogLike(LOG).getAddress("MCD_VAT"));
        vow = VowLike(ChainlogLike(LOG).getAddress("MCD_VOW"));
        farm = StakingRewardsLike(ChainlogLike(LOG).getAddress("REWARDS_LSSKY_USDS"));

        kicker = Kicker(FlapperDeploy.deployKicker({
            deployer: address(this),
            owner:    PAUSE_PROXY
        }));
        
        // Note - this part emulates the spell initialization
        vm.startPrank(PAUSE_PROXY);
        KickerConfig memory kickerCfg = KickerConfig({
            khump:       -20_000e45,
            kbump:       5_000e45,
            chainlogKey: "KICK"
        });
        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        FlapperInit.initKicker(dss, address(kicker), kickerCfg);
        vm.stopPrank();

        assertEq(vow.bump(), 0);
        assertEq(vow.hump(), type(uint256).max);
        assertEq(kicker.kbump(), 5_000e45);
        assertEq(kicker.khump(), -20_000e45);
        assertEq(vat.wards(address(kicker)), 1);
        assertEq(splitter.wards(address(kicker)), 1);
        assertEq(splitter.wards(address(vow)), 0);
        assertEq(dss.chainlog.getAddress("KICK"), address(kicker));

        // Add initial liquidity if needed
        (uint256 reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, SKY);
        uint256 minimalUsdsReserve = 280_000 * WAD;
        if (reserveUsds < minimalUsdsReserve) {
            _setMedianPrice(0.06 * 1e18);
            changeUniV2Price(uint256(medianizer.read()), SKY, UNIV2_SKY_USDS_PAIR);
            (reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, USDS, SKY);
            if (reserveUsds < minimalUsdsReserve) {
                topUpLiquidity(minimalUsdsReserve - reserveUsds, SKY, UNIV2_SKY_USDS_PAIR);
            }
        } else {
            _setMedianPrice(uniV2UsdsForGem(WAD, SKY));
        }

        // Allow Test contract to read from Scribe oracle
        vm.store(address(medianizer), keccak256(abi.encode(address(this), uint256(2))), bytes32(uint256(1)));
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function _setMedianPrice(uint256 price) internal {
        vm.store(address(medianizer), bytes32(uint256(4)), bytes32(price));
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
        uint256 wbump = kicker.kbump() / RAY;
        uint256 actual = uniV2GemForUsds(wbump, gem);
        uint256 ref    = refAmountOut(wbump, pip);
        return actual * WAD / ref;
    }

    function doKick(bool expectRevert) internal {
        if (block.timestamp < splitter.zzz() + splitter.hop()) {
            vm.warp(splitter.zzz() + splitter.hop());
        }

        uint256 initialVowVatDai = vat.dai(address(vow));
        uint256 initialUsdsJoinVatDai = vat.dai(USDS_JOIN);
        uint256 initialSky = GemLike(SKY).balanceOf(address(PAUSE_PROXY));
        uint256 initialReserveUsds = GemLike(USDS).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialReserveSky = GemLike(SKY).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialFarmUsds = GemLike(USDS).balanceOf(address(farm));
        uint256 prevRewardRate = farm.rewardRate();
        uint256 farmLeftover = block.timestamp >= farm.periodFinish() ? 0 : farm.rewardRate() * (farm.periodFinish() - block.timestamp);
        uint256 farmReward = kicker.kbump() * (WAD - splitter.burn()) / RAD;
        uint256 prevLastUpdateTime = farm.lastUpdateTime();

        if (expectRevert) {
            vm.expectRevert("Kicker/insufficient-allowance");
            kicker.flap();
        } else {
            vm.expectEmit(false, false, false, true);
            emit Kick(kicker.kbump(), kicker.kbump() * splitter.burn() / RAD, farmReward);
            kicker.flap();
            vow.heal(_min(kicker.kbump(), vat.dai(address(vow))));

            assertEq(vat.dai(address(vow)), initialVowVatDai > kicker.kbump() ? initialVowVatDai - kicker.kbump() : 0);
            assertEq(vat.dai(USDS_JOIN), initialUsdsJoinVatDai + kicker.kbump());
            assertEq(vat.dai(address(splitter)), 0);
            assertEq(vat.dai(address(kicker)), 0);

            assertEq(GemLike(USDS).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveUsds + kicker.kbump() * splitter.burn() / RAD);
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
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        Kicker k = new Kicker(address(vat), address(vow), address(splitter));

        assertEq(address(k.vat()), address(vat));
        assertEq(address(k.vow()), address(vow));
        assertEq(address(k.splitter()), address(splitter));
        assertEq(vat.can(address(kicker), address(splitter)), 1);
        assertEq(k.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(kicker), "Kicker");
    }

    function testFileUint() public {
        checkFileUint(address(kicker), "Kicker", ["kbump"]);
    }

    event File(bytes32 indexed what, int256 data);
    function checkFileInt(address _base, string memory _contractName, string[] memory _values) internal {
        FileLike2 base = FileLike2(_base);
        uint256 ward = base.wards(address(this));

        // Ensure we have admin access
        GodMode.setWard(_base, address(this), 1);

        // First check an invalid value
        vm.expectRevert(abi.encodePacked(_contractName, "/file-unrecognized-param"));
        base.file("an invalid value", int256(1));

        // Next check each value is valid and updates the target storage slot
        for (uint256 i = 0; i < _values.length; i++) {
            string memory value = _values[i];
            bytes32 valueB32;
            assembly {
                valueB32 := mload(add(value, 32))
            }

            // Read original value
            (bool success, bytes memory result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "()"))));
            assertTrue(success);
            int256 origData = abi.decode(result, (int256));
            int256 newData;
            unchecked {
                newData = origData + 1;   // Overflow is fine
            }

            // Update value
            vm.expectEmit(true, false, false, true);
            emit File(valueB32, newData);
            base.file(valueB32, newData);

            // Confirm it was updated successfully
            (success, result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "()"))));
            assertTrue(success);
            int256 data = abi.decode(result, (int256));
            assertEq(data, newData);

            // Reset value to original
            vm.expectEmit(true, false, false, true);
            emit File(valueB32, origData);
            base.file(valueB32, origData);
        }

        // Finally check that file is authed
        base.deny(address(this));
        vm.expectRevert(abi.encodePacked(_contractName, "/not-authorized"));
        base.file("some value", int256(1));

        // Reset admin access to what it was
        GodMode.setWard(_base, address(this), ward);
    }
    function checkFileInt(address _base, string memory _contractName, string[1] memory _values) internal {
        string[] memory values = new string[](1);
        values[0] = _values[0];
        checkFileInt(_base, _contractName, values);
    }

    function testFileInt() public {
        checkFileInt(address(kicker), "Kicker", ["khump"]);
    }

    function testKick() public {
        doKick(false);
    }

    function testKickNegativeSurplus() public {
        // // Heal if needed
        // uint256 vatSinVow = vat.sin(address(vow));
        // uint256 vatDaiVow = vat.dai(address(vow));
        // if (vatSinVow > vatDaiVow && vatSinVow > vow.Sin() + vow.Ash()) {
        //     vow.heal(vatSinVow - vow.Sin() - vow.Ash());
        // }
        // vatSinVow = vat.sin(address(vow));
        // vatDaiVow = vat.dai(address(vow));

        stdstore.target(address(vow)).sig("Sin()").checked_write(
            uint256(0)
        );
        stdstore.target(address(vat)).sig("sin(address)").with_key(address(vow)).depth(0).checked_write(
            uint256(0)
        );
        stdstore.target(address(vat)).sig("dai(address)").with_key(address(vow)).depth(0).checked_write(
            uint256(2_500e45)
        );

        assertEq(vow.Sin(), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.dai(address(vow)), 2_500e45);

        vm.warp(splitter.zzz() + splitter.hop());
        doKick(false);

        assertEq(vat.sin(address(vow)), 2_500e45);
        assertEq(vat.dai(address(vow)), 0);

        vm.warp(splitter.zzz() + splitter.hop());
        doKick(false);

        assertEq(vat.sin(address(vow)), 7_500e45);
        assertEq(vat.dai(address(vow)), 0);

        vm.warp(splitter.zzz() + splitter.hop());
        doKick(false);

        assertEq(vat.sin(address(vow)), 12_500e45);
        assertEq(vat.dai(address(vow)), 0);

        vm.warp(splitter.zzz() + splitter.hop());
        doKick(false);

        assertEq(vat.sin(address(vow)), 17_500e45);
        assertEq(vat.dai(address(vow)), 0);

        vm.warp(splitter.zzz() + splitter.hop());
        doKick(true);
    }

    function testKickBurnOnly() public {
        vm.prank(PAUSE_PROXY); splitter.file("burn", WAD);

        doKick(false);
    }

    function testKickZeroBurn() public {
        vm.prank(PAUSE_PROXY); splitter.file("burn", 0);

        doKick(false);
    }

    function testKickAfterHop() public {
        doKick(false);
        vm.warp(block.timestamp + splitter.hop());

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);
        // doKick(false);
    }

    function testKickBeforeHop() public {
        doKick(false);
        vm.warp(block.timestamp + splitter.hop() - 1 seconds);

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);
        vm.expectRevert("Splitter/kicked-too-soon");
        kicker.flap();
    }

    function testKickAfterStoppedWithHop() public {
        uint256 initialHop = splitter.hop();

        doKick(false);
        vm.warp(block.timestamp + splitter.hop());

        // make sure the slippage of the first kick doesn't block us
        uint256 _marginalWant = marginalWant(SKY, address(medianizer));
        vm.prank(PAUSE_PROXY); flapper.file("want", _marginalWant * 99 / 100);

        vm.prank(PAUSE_PROXY); splitter.file("hop", type(uint256).max);
        vm.expectRevert(bytes(abi.encodeWithSignature("Panic(uint256)", 0x11))); // arithmetic error
        kicker.flap();

        vm.prank(PAUSE_PROXY); splitter.file("hop", initialHop);
        kicker.flap();
    }
}
