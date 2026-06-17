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
    function kbump() external view returns (uint256);
    function splitter() external view returns (address);
    function file(bytes32, uint256) external;
}

interface SplitterLike {
    function burn() external view returns (uint256);
    function hop()  external view returns (uint256);
    function farm() external view returns (address);
    function file(bytes32, uint256) external;
}

interface FarmOwnerLike {
    function setRewardsDuration(uint256) external;
}

contract SBEBeam {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => uint256) public buds;
    Cfg     public kbumpCfg; // [rad]     Range for Kicker.kbump
    Cfg     public burnCfg;  // [wad]     Range for Splitter.burn
    Cfg     public hopCfg;   // [seconds] Range for Splitter.hop (also applied to farm.rewardsDuration)
    uint8   public bad;      // Circuit breaker flag
    uint64  public tau;      // Cooldown period between set() calls in seconds
    uint128 public toc;      // Last time when set() was called (Unix timestamp)

    // --- structs ---

    struct Cfg {
        uint256 min;  // Minimum allowed value
        uint256 max;  // Maximum allowed value
        uint256 step; // Maximum allowed change per update (0 means "not configured")
    }

    // --- immutables ---

    KickerLike    public immutable kicker;
    SplitterLike  public immutable splitter;
    FarmOwnerLike public immutable farmOwner;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed id, bytes32 indexed what, uint256 data);
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
        require(bad == 0, "SBEBeam/module-halted");
        _;
    }

    // --- constructor ---

    constructor(address _kicker, address _farmOwner) {
        kicker    = KickerLike(_kicker);
        splitter  = SplitterLike(kicker.splitter());
        farmOwner = FarmOwnerLike(_farmOwner);

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

    function file(bytes32 what, uint256 data) external auth {
        if (what == "bad") {
            require(data == 0 || data == 1, "SBEBeam/invalid-bad-value");
            bad = uint8(data);
        } else if (what == "tau") {
            require(data <= type(uint64).max, "SBEBeam/invalid-tau-value");
            tau = uint64(data);
        } else if (what == "toc") {
            require(data <= type(uint128).max, "SBEBeam/invalid-toc-value");
            toc = uint128(data);
        } else revert("SBEBeam/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 id, bytes32 what, uint256 data) external auth {
        Cfg storage cfg;
        if      (id == "kbump") cfg = kbumpCfg;
        else if (id == "burn")  cfg = burnCfg;
        else if (id == "hop")   cfg = hopCfg;
        else revert("SBEBeam/file-unrecognized-id");

        if (what == "min") {
            require(data <= cfg.max, "SBEBeam/min-too-high");
            cfg.min = data;
        } else if (what == "max") {
            require(data >= cfg.min, "SBEBeam/max-too-low");
            cfg.max = data;
        } else if (what == "step") {
            cfg.step = data;
        } else revert("SBEBeam/file-unrecognized-param");
        emit File(id, what, data);
    }

    // --- internals ---

    function _check(uint256 val, uint256 old, Cfg memory cfg) internal pure {
        require(cfg.step > 0,   "SBEBeam/value-not-configured");
        require(val >= cfg.min, "SBEBeam/below-min");
        require(val <= cfg.max, "SBEBeam/above-max");

        if (old < cfg.min) {
            old = cfg.min;
        } else if (old > cfg.max) {
            old = cfg.max;
        }

        uint256 delta = val > old ? val - old : old - val;
        require(delta <= cfg.step, "SBEBeam/delta-above-step");
    }

    // --- execution ---

    // Notes:
    // - It is intended to rewrite the same values, emit the event, and reset the toc count, even if there is no change.
    function set(uint256 kbump, uint256 burn, uint256 hop) external toll good {
        require(block.timestamp >= tau + toc, "SBEBeam/too-early");
        toc = uint128(block.timestamp);

        _check(kbump, kicker.kbump(),  kbumpCfg);
        _check(burn,  splitter.burn(), burnCfg);
        _check(hop,   splitter.hop(),  hopCfg);

        kicker.file("kbump", kbump);
        splitter.file("burn", burn);
        splitter.file("hop", hop);
        farmOwner.setRewardsDuration(hop);

        emit Set(kbump, burn, hop);
    }
}
