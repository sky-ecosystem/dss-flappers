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
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

interface VatLike {
    function dai(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function hope(address) external;
    function suck(address, address, uint256) external;
}

interface VowLike {
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
}

interface SplitterLike {
    function kick(uint256, uint256) external returns (uint256);
}

contract Kicker {
    // --- storage variables ---

    mapping(address usr => uint256 allowed) public wards;
    uint256 public kbump;
    int256  public khump;

    // --- immutables ---

    VatLike      public immutable vat;
    VowLike      public immutable vow;
    SplitterLike public immutable splitter;

    // --- immutables ---

    constructor(address vat_, address vow_, address splitter_) {
        vat = VatLike(vat_);
        vow = VowLike(vow_);
        splitter = SplitterLike(splitter_);
        vat.hope(splitter_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, int256 data);

    // --- modifiers ---

    modifier auth {
        require(wards[msg.sender] == 1, "Kicker/not-authorized");
        _;
    }

    // --- internals ---

    function _toInt256(uint256 x) internal pure returns (int256 y) {
        require(x <= uint256(type(int256).max), "Kicker/overflow");
        y = int256(x);
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

    function file(bytes32 what, uint256 data) external auth {
        if (what == "kbump") {
            kbump = data;
        } else revert("Kicker/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, int256 data) external auth {
        if (what == "khump") {
            khump = data;
        } else revert("Kicker/file-unrecognized-param");
        emit File(what, data);
    }

    // --- execution ---

    function flap() external returns (uint256 id) {
        require(_toInt256(vat.dai(address(vow))) >= _toInt256(vat.sin(address(vow))) + _toInt256(kbump) + khump, "Kicker/insufficient-allowance");
        // require(vat.sin(address(vow)) - vow.Sin() - vow.Ash() == 0 || vat.dai(address(vow)) == 0 , "Kicker/not-healed");
        vat.suck(address(vow), address(this), kbump);
        id = splitter.kick(kbump, 0);
    }
}
