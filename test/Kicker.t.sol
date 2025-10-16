// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
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
import "./helpers/UniswapV2Library.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
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

    DssInstance          dss;
    address              pauseProxy;
    address              usds;
    address              sky;
    address              usdsJoin;
    Splitter             splitter;
    MedianizerLike       medianizer;
    StakingRewardsLike   farm;
    Kicker               kicker;

    address LOG                 = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address UNIV2_FACTORY       = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address UNIV2_SKY_USDS_PAIR = 0x2621CC0B3F3c079c1Db0E80794AA24976F0b9e3c;

    event Kick(uint256 tot, uint256 lot, uint256 pay);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(LOG);
        pauseProxy = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        usds = ChainlogLike(LOG).getAddress("USDS");
        sky = ChainlogLike(LOG).getAddress("SKY");
        usdsJoin = ChainlogLike(LOG).getAddress("USDS_JOIN");
        splitter = Splitter(ChainlogLike(LOG).getAddress("MCD_SPLIT"));
        medianizer = MedianizerLike(ChainlogLike(LOG).getAddress("FLAP_SKY_ORACLE"));
        farm = StakingRewardsLike(ChainlogLike(LOG).getAddress("REWARDS_LSSKY_USDS"));

        kicker = Kicker(FlapperDeploy.deployKicker({
            deployer: address(this),
            owner:    pauseProxy
        }));
        
        // Note - this part emulates the spell initialization
        vm.startPrank(pauseProxy);
        KickerConfig memory kickerCfg = KickerConfig({
            khump:       -20_000e45,
            kbump:       5_000e45,
            chainlogKey: "KICK"
        });
        FlapperInit.initKicker(dss, address(kicker), kickerCfg);
        vm.stopPrank();

        assertEq(dss.vow.bump(), 0);
        assertEq(dss.vow.hump(), type(uint256).max);
        assertEq(dss.vow.dump(), 0);
        assertEq(dss.vow.sump(), type(uint256).max);
        assertEq(kicker.kbump(), 5_000e45);
        assertEq(kicker.khump(), -20_000e45);
        assertEq(dss.vat.wards(address(kicker)), 1);
        assertEq(splitter.wards(address(kicker)), 1);
        assertEq(dss.chainlog.getAddress("KICK"), address(kicker));

        // Add initial liquidity if needed
        (uint256 reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, usds, sky);
        uint256 minimalUsdsReserve = 280_000 * WAD;
        if (reserveUsds < minimalUsdsReserve) {
            _setMedianPrice(0.06 * 1e18);
            _changeUniV2Price(uint256(medianizer.read()), sky, UNIV2_SKY_USDS_PAIR);
            (reserveUsds, ) = UniswapV2Library.getReserves(UNIV2_FACTORY, usds, sky);
            if (reserveUsds < minimalUsdsReserve) {
                _topUpLiquidity(minimalUsdsReserve - reserveUsds, sky, UNIV2_SKY_USDS_PAIR);
            }
        } else {
            _setMedianPrice(_uniV2UsdsForGem(WAD, sky));
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

    function _uniV2UsdsForGem(uint256 amountIn, address gem) internal view returns (uint256 amountOut) {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, usds, gem);
        return UniswapV2Library.getAmountOut(amountIn, reserveGem, reserveUsds);
    }

    function _changeUniV2Price(uint256 usdsForGem, address gem, address pair) internal {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, usds, gem);
        uint256 currentUsdsForGem = reserveUsds * WAD / reserveGem;

        // neededReserveUsds * WAD / neededReserveSky = usdsForGem;
        if (currentUsdsForGem > usdsForGem) {
            deal(gem, pair, reserveUsds * WAD / usdsForGem);
        } else {
            deal(usds, pair, reserveGem * usdsForGem / WAD);
        }
        PairLike(pair).sync();
    }

    function _topUpLiquidity(uint256 usdsAmt, address gem, address pair) internal {
        (uint256 reserveUsds, uint256 reserveGem) = UniswapV2Library.getReserves(UNIV2_FACTORY, usds, gem);
        uint256 gemAmt = UniswapV2Library.quote(usdsAmt, reserveUsds, reserveGem);

        deal(usds, address(this), GemLike(usds).balanceOf(address(this)) + usdsAmt);
        deal(gem, address(this), GemLike(gem).balanceOf(address(this)) + gemAmt);

        GemLike(usds).transfer(pair, usdsAmt);
        GemLike(gem).transfer(pair, gemAmt);
        uint256 liquidity = PairLike(pair).mint(address(this));
        assertGt(liquidity, 0);
        assertGe(GemLike(pair).balanceOf(address(this)), liquidity);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        Kicker k = new Kicker(address(dss.vow), address(splitter));

        assertEq(address(k.vat()), address(dss.vat));
        assertEq(address(k.vow()), address(dss.vow));
        assertEq(address(k.splitter()), address(splitter));
        assertEq(dss.vat.can(address(kicker), address(splitter)), 1);
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

    function testVowFlapFails() public {
        if (block.timestamp < splitter.zzz() + splitter.hop()) {
            vm.warp(splitter.zzz() + splitter.hop());
        }

        vm.expectRevert();
        dss.vow.flap();
        kicker.flap();
    }

    function _doKick() internal {
        if (block.timestamp < splitter.zzz() + splitter.hop()) {
            vm.warp(splitter.zzz() + splitter.hop());
        }

        uint256 initialVowVatDai = dss.vat.dai(address(dss.vow));
        uint256 initialUsdsJoinVatDai = dss.vat.dai(usdsJoin);
        uint256 initialSky = GemLike(sky).balanceOf(pauseProxy);
        uint256 initialReserveUsds = GemLike(usds).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialReserveSky = GemLike(sky).balanceOf(UNIV2_SKY_USDS_PAIR);
        uint256 initialFarmUsds = GemLike(usds).balanceOf(address(farm));
        uint256 prevRewardRate = farm.rewardRate();
        uint256 farmLeftover = block.timestamp >= farm.periodFinish() ? 0 : farm.rewardRate() * (farm.periodFinish() - block.timestamp);
        uint256 farmReward = kicker.kbump() * (WAD - splitter.burn()) / RAD;
        uint256 prevLastUpdateTime = farm.lastUpdateTime();

        vm.expectEmit(false, false, false, true);
        emit Kick(kicker.kbump(), kicker.kbump() * splitter.burn() / RAD, farmReward);
        kicker.flap();
        dss.vow.heal(_min(kicker.kbump(), dss.vat.dai(address(dss.vow))));

        assertEq(dss.vat.dai(address(dss.vow)), initialVowVatDai > kicker.kbump() ? initialVowVatDai - kicker.kbump() : 0);
        assertEq(dss.vat.dai(usdsJoin), initialUsdsJoinVatDai + kicker.kbump());
        assertEq(dss.vat.dai(address(splitter)), 0);
        assertEq(dss.vat.dai(address(kicker)), 0);

        assertEq(GemLike(usds).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveUsds + kicker.kbump() * splitter.burn() / RAD);
        if (splitter.burn() == 0) {
            assertEq(GemLike(sky).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveSky);
            assertEq(GemLike(sky).balanceOf(pauseProxy), initialSky);
        } else {
            assertLt(GemLike(sky).balanceOf(UNIV2_SKY_USDS_PAIR), initialReserveSky);
            assertGt(GemLike(sky).balanceOf(pauseProxy), initialSky);
        }

        assertEq(GemLike(usds).balanceOf(address(farm)), initialFarmUsds + farmReward);
        if (splitter.burn() == WAD) {
            assertEq(farm.rewardRate(), prevRewardRate);
            assertEq(farm.lastUpdateTime(), prevLastUpdateTime);
        } else {
            assertEq(farm.rewardRate(), (farmLeftover + farmReward) / farm.rewardsDuration());
            assertEq(farm.lastUpdateTime(), block.timestamp);
        }
    }

    function _initForTestWithSin() internal {
        stdstore.target(address(dss.vow)).sig("Sin()").checked_write(
            uint256(0)
        );
        stdstore.target(address(dss.vat)).sig("sin(address)").with_key(address(dss.vow)).depth(0).checked_write(
            uint256(0)
        );
        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(dss.vow)).depth(0).checked_write(
            uint256(2_500e45)
        );

        assertEq(dss.vow.Sin(), 0);
        assertEq(dss.vat.sin(address(dss.vow)), 0);
        assertEq(dss.vat.dai(address(dss.vow)), 2_500e45);
    }

    function _doKicksWithSin() internal {
        _initForTestWithSin();

        _doKick();

        assertEq(dss.vat.sin(address(dss.vow)), 2_500e45);
        assertEq(dss.vat.dai(address(dss.vow)), 0);

        _doKick();

        assertEq(dss.vat.sin(address(dss.vow)), 7_500e45);
        assertEq(dss.vat.dai(address(dss.vow)), 0);

        _doKick();

        assertEq(dss.vat.sin(address(dss.vow)), 12_500e45);
        assertEq(dss.vat.dai(address(dss.vow)), 0);

        _doKick();

        assertEq(dss.vat.sin(address(dss.vow)), 17_500e45);
        assertEq(dss.vat.dai(address(dss.vow)), 0);

        vm.expectRevert("Kicker/flap-threshold-not-reached");
        kicker.flap();
    }

    function testFlap() public {
        _doKick();
    }

    function testFlapWithSin() public {
        _doKicksWithSin();
    }

    function testFlapBurnOnly() public {
        vm.prank(pauseProxy); splitter.file("burn", WAD);

        _doKick();
    }

    function testFlapWithSinBurnOnly() public {
        vm.prank(pauseProxy); splitter.file("burn", WAD);

        _doKicksWithSin();
    }

    function testFlapZeroBurn() public {
        vm.prank(pauseProxy); splitter.file("burn", 0);

        _doKick();
    }

    function testFlapWithSinZeroBurn() public {
        vm.prank(pauseProxy); splitter.file("burn", 0);

        _doKicksWithSin();
    }

    function testFlapNotLive() public {
        assertEq(splitter.live(), 1);
        vm.prank(pauseProxy); dss.vow.cage();
        assertEq(splitter.live(), 0);
        vm.expectRevert("Splitter/not-live");
        kicker.flap();
    }
}
