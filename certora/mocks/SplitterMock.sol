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
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

interface VatLike {
    function move(address, address, uint256) external;
}

// Stand-in for the Splitter, modelling only what a kick does to its caller: the gating
// (auth, live and hop) and the move of the surplus out of the caller and into the
// Splitter, which is also what keeps the `vat.can(kicker, splitter)` requirement in
// scope. `tot` is recorded so the caller can be checked to kick the right amount.
//
// The distribution of the surplus (burn split, usdsJoin exits, flapper and farm) is left
// out on purpose: it is downstream of the move, invisible to the Kicker, and already
// verified in Splitter.spec for an arbitrary caller and an arbitrary `tot`.
contract SplitterMock {
    mapping (address => uint256) public wards;
    uint256 public live;
    uint256 public hop;
    uint256 public zzz;
    uint256 public lastTot;

    VatLike public immutable vat;

    constructor(address vat_) {
        vat = VatLike(vat_);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "SplitterMock/not-authorized");
        _;
    }

    function kick(uint256 tot, uint256) external auth returns (uint256) {
        require(live == 1, "SplitterMock/not-live");

        require(block.timestamp >= zzz + hop, "SplitterMock/kicked-too-soon");
        zzz = block.timestamp;

        vat.move(msg.sender, address(this), tot);

        lastTot = tot;
        return 0;
    }
}
