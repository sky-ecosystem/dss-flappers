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
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-interfaces/Interfaces.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { SplitterInstance } from "./SplitterInstance.sol";
import { FlapperUniV2 } from "src/FlapperUniV2.sol";
import { FlapperUniV2SwapOnly } from "src/FlapperUniV2SwapOnly.sol";
import { SplitterMom } from "src/SplitterMom.sol";
import { OracleWrapper } from "src/OracleWrapper.sol";
import { Splitter } from "src/Splitter.sol";
import { Kicker } from "src/Kicker.sol";

library FlapperDeploy {

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    function deployFlapperUniV2(
        address deployer,
        address owner,
        address spotter,
        address usds,
        address gem,
        address pair,
        address receiver,
        bool    swapOnly
    ) internal returns (address flapper) {
        flapper =
            swapOnly ? address(new FlapperUniV2SwapOnly(spotter, usds, gem, pair, receiver))
                     : address(new FlapperUniV2(spotter, usds, gem, pair, receiver))
        ;

        ScriptTools.switchOwner(flapper, deployer, owner);
    }

    function deployOracleWrapper(
        address pip,
        address flapper,
        uint256 divisor
    ) internal returns (address wrapper) {
        wrapper = address(new OracleWrapper(pip, flapper, divisor));
    }

    function deploySplitter(
        address deployer,
        address owner,
        address usdsJoin
    ) internal returns (SplitterInstance memory splitterInstance) {
        address splitter = address(new Splitter(usdsJoin));
        address mom = address(new SplitterMom(splitter));

        ScriptTools.switchOwner(splitter, deployer, owner);
        DSAuthAbstract(mom).setOwner(owner);

        splitterInstance.splitter = splitter;
        splitterInstance.mom      = mom;
    }

    function deployKicker(
        address deployer,
        address owner
    ) internal returns (address kicker) {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        kicker = address(new Kicker(
                                dss.chainlog.getAddress("MCD_VOW"),
                                dss.chainlog.getAddress("MCD_SPLIT")));

        ScriptTools.switchOwner(kicker, deployer, owner);
    }
}
