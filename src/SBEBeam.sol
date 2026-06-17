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
    Cfg     public kbumpCfg;  // [rad]     Range for Kicker.kbump
    Cfg     public burnCfg;   // [wad]     Range for Splitter.burn
    Cfg     public hopCfg;    // [seconds] Range for Splitter.hop (also applied to farm.rewardsDuration)
    uint256 public ratioStep; // [bps]     Maximum allowed ratio (kbump / hop) change per update, relative to its current value
    uint64  public tau;       // Cooldown period between set() calls in seconds
    uint128 public toc;       // Last time when set() was called (Unix timestamp)

    // --- structs ---

    struct Cfg {
        uint256 min;  // Minimum allowed value
        uint256 max;  // Maximum allowed value
        uint256 step; // [bps] Maximum allowed change per update, relative to the current value
    }

    // --- immutables ---

    KickerLike    public immutable kicker;
    SplitterLike  public immutable splitter;
    FarmOwnerLike public immutable farmOwner;

    // --- constants ---

    uint256 internal constant BPS = 100_00;

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
        require(splitter.hop() < type(uint256).max, "SBEBeam/module-halted");
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
        if (what == "ratioStep") {
            ratioStep = data;
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

    function _check(string memory field, uint256 val, uint256 prev, Cfg memory cfg) internal pure returns (uint256 prevBounded) {
        require(val >= cfg.min, string(abi.encodePacked("SBEBeam/", field, "-below-min")));
        require(val <= cfg.max, string(abi.encodePacked("SBEBeam/", field, "-above-max")));

        prevBounded = prev < cfg.min
                      ? cfg.min
                      : prev > cfg.max
                        ? cfg.max
                        : prev;

        uint256 delta = val > prevBounded ? val - prevBounded : prevBounded - val;
        require(delta <= prevBounded * cfg.step / BPS, string(abi.encodePacked("SBEBeam/", field, "-delta-above-step")));
    }

    // --- execution ---

    // Notes:
    // - It is intended to rewrite the same values, emit the event, and reset the toc count, even if there is no change.
    function set(uint256 kbump, uint256 burn, uint256 hop) external toll good {
        require(block.timestamp >= tau + toc, "SBEBeam/too-early");
        toc = uint128(block.timestamp);

        uint256 prevKbump = kicker.kbump();
        uint256 prevHop = splitter.hop();

        uint256 prevKbumpBounded = _check("kbump", kbump, prevKbump, kbumpCfg);
        uint256 prevHopBounded = _check("hop", hop, prevHop, hopCfg);
        _check("burn", burn, splitter.burn(), burnCfg);

        uint256 prevRatio = prevKbumpBounded / prevHopBounded;
        uint256 newRatio  = kbump / hop;

        uint256 delta = prevRatio > newRatio ? prevRatio - newRatio : newRatio - prevRatio;
        require(delta <= prevRatio * ratioStep / BPS, "SBEBeam/ratio-delta-above-step");

        kicker.file("kbump", kbump);
        splitter.file("burn", burn);
        if (hop != prevHop) {
            // Avoid to extend duration of current stream if hop did not change
            splitter.file("hop", hop);
            farmOwner.setRewardsDuration(hop);
        }

        emit Set(kbump, burn, hop);
    }
}
