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

import "forge-std/Test.sol";

import { DssInstance, MCD } from "dss-test/MCD.sol";
import { FlapperDeploy } from "deploy/FlapperDeploy.sol";
import { FlapperInit } from "deploy/FlapperInit.sol";
import { OracleWrapper } from "src/OracleWrapper.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface OsmLike {
    function src() external view returns (address);
}

interface PipLike {
    function read() external view returns (bytes32);
    function kiss(address) external;
    function diss(address) external;
}

contract OracleWrapperTest is Test {
    PipLike public medianizer;
    PipLike public oracleWrapper;
    uint256 public medianizerPrice;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address PAUSE_PROXY;
    address PIP_ETH;

    uint256 constant WAD = 10 ** 18;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        PAUSE_PROXY = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        PIP_ETH     = ChainlogLike(LOG).getAddress("PIP_ETH");

        medianizer = PipLike(OsmLike(PIP_ETH).src());

        // Get current price
        vm.store(address(medianizer), keccak256(abi.encode(address(this), uint256(2))), bytes32(uint256(1)));
        medianizerPrice = uint256(medianizer.read());
        assertGt(medianizerPrice, 0);
        vm.store(address(medianizer), keccak256(abi.encode(address(this), uint256(2))), bytes32(uint256(0)));

        oracleWrapper = PipLike(FlapperDeploy.deployOracleWrapper(address(medianizer), address(this), 1800));

        // Emulate spell
        vm.store(address(medianizer), keccak256(abi.encode(PAUSE_PROXY, uint256(0))), bytes32(uint256(1)));
        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        vm.startPrank(PAUSE_PROXY);
        FlapperInit.initOracleWrapper(dss, address(oracleWrapper), 1800, "ORACLE_WRAPPER");
        vm.stopPrank();
    }

    function testInitsChainlogValue() public view {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        assertEq(dss.chainlog.getAddress("ORACLE_WRAPPER"), address(oracleWrapper));
    }

    function testRead() public view {
        assertEq(oracleWrapper.read(), bytes32(medianizerPrice / 1800));
    }

    // function testReadInvalidPrice() public {
    //     vm.store(address(medianizer), bytes32(uint256(1)), 0); // set val (and age) to 0
    //     vm.expectRevert("Median/invalid-price-feed");
    //     oracleWrapper.read();
    // }

    function testUnauthorizedReader() public {
        vm.prank(address(123));
        vm.expectRevert("OracleWrapper/unauthorized-reader");
        oracleWrapper.read();
    }
}
