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

interface KickerLike {
    function splitter() external view returns (address);
    function file(bytes32, uint256) external;
}

interface SplitterLike {
    function hop()  external view returns (uint256);
    function farm() external view returns (address);
    function file(bytes32, uint256) external;
}

interface FarmOwnerLike {
    function farm() external view returns (address);
    function setRewardsDuration(uint256) external;
}

interface FarmLike {
    function rewardsDuration() external view returns (uint256);
}

contract SBEBeam {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => uint256) public buds;
    FarmOwnerLike public farmOwner; // Owner of the Splitter.farm, used to re-rate the farm's rewardsDuration
    uint256       public maxKbump;  // [rad]     Maximum allowed value for Kicker.kbump
    uint256       public minHop;    // [seconds] Minimum allowed value for Splitter.hop (also applied to farm.rewardsDuration)
    uint256       public maxRate;   // [rad/s]   Maximum allowed burn rate (kbump / hop)
    uint64        public tau;       // Cooldown period between set() calls in seconds
    uint128       public toc;       // Last time when set() was called (Unix timestamp)

    // --- immutables ---

    KickerLike   public immutable kicker;
    SplitterLike public immutable splitter;

    // --- constants ---

    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAY = 10 ** 27;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event Set(uint256 kbump, uint256 burn, uint256 hop);

    // --- modifiers ---

    modifier auth {
        require(wards[msg.sender] == 1, "SBEBeam/not-authorized");
        _;
    }

    modifier toll {
        require(buds[msg.sender] == 1, "SBEBeam/not-facilitator");
        _;
    }

    modifier good {
        require(splitter.hop() < type(uint256).max, "SBEBeam/module-halted");
        _;
    }

    // --- constructor ---

    constructor(address _kicker) {
        kicker   = KickerLike(_kicker);
        splitter = SplitterLike(kicker.splitter());

        minHop = 5 minutes;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "farmOwner") {
            farmOwner = FarmOwnerLike(data);
        } else revert("SBEBeam/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxKbump") {
            maxKbump = data;
        } else if (what == "minHop") {
            require(data >= 5 minutes, "SBEBeam/minHop-too-low");
            minHop = data;
        } else if (what == "maxRate") {
            maxRate = data;
        } else if (what == "tau") {
            require(data <= type(uint64).max, "SBEBeam/invalid-tau-value");
            tau = uint64(data);
        } else if (what == "toc") {
            require(data <= type(uint128).max, "SBEBeam/invalid-toc-value");
            toc = uint128(data);
        } else revert("SBEBeam/file-unrecognized-param");
        emit File(what, data);
    }

    // --- execution ---

    // Notes:
    // - It is intended to rewrite the same values, emit the event, and reset the toc count, even if there is no change.
    // - Only the throughput-increasing directions are bounded: kbump is capped at maxKbump, hop is
    //   floored at minHop, and the burn rate (kbump / hop) is capped at maxRate. Lowering kbump or
    //   raising hop is always allowed; at worst it stalls the burn stream, which governance can revive.
    // - burn is capped at WAD (100%); a higher value would make Splitter.kick underflow and halt.
    // - kbump must be a whole multiple of RAY, preserving the Kicker deploy invariant and avoiding kick dust.
    // - hop must stay below type(uint256).max: that value is the halt sentinel (see the good modifier),
    //   reserved for governance, so a facilitator cannot use set() to halt and lock itself out of the module.
    // - Kicker.khump (the flap threshold) is deliberately left out of the set knobs: it is not a value that needs regular
    //   tuning, and changing it is a more structural governance decision better routed through the full governance process.
    function set(uint256 kbump, uint256 burn, uint256 hop) external toll good {
        require(block.timestamp >= tau + toc,        "SBEBeam/too-early");
        require(kbump <= maxKbump,                   "SBEBeam/kbump-above-max");
        require(kbump % RAY == 0,                    "SBEBeam/kbump-not-multiple-of-RAY");
        require(burn <= WAD,                         "SBEBeam/burn-above-max");
        require(hop >= minHop,                       "SBEBeam/hop-below-min");
        require(hop < type(uint256).max,             "SBEBeam/hop-halts-engine");
        require(kbump / hop <= maxRate,              "SBEBeam/rate-above-max");
        require(burn == WAD ||
                splitter.farm() == farmOwner.farm(), "SBEBeam/farm-sanity-failed");

        toc = uint128(block.timestamp);

        kicker.file("kbump", kbump);
        splitter.file("burn", burn);
        splitter.file("hop", hop);

        // When burn == WAD all surplus goes to the burn engine and nothing is
        // staked, so there is no farm reward stream to re-rate. Otherwise:
        // - avoid extending the duration of the current stream if hop did not change, and
        // - indirectly allow fixing a possible desync between splitter and the
        //   farm for whatever reason that could have happened (included a prior burn=WAD).
        if (burn < WAD && hop != FarmLike(farmOwner.farm()).rewardsDuration()) {
            farmOwner.setRewardsDuration(hop);
        }

        emit Set(kbump, burn, hop);
    }
}
