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

interface VatLike {
    function move(address, address, uint256) external;
    function hope(address) external;
}

interface UsdsJoinLike {
    function vat() external view returns (address);
    function exit(address, uint256) external;
}

interface FlapLike {
    function exec(uint256) external;
    function cage() external;
}

interface FarmLike {
    function notifyRewardAmount(uint256 reward) external;
}

contract Splitter {
    mapping (address => uint256) public wards;
    uint256     public           live;    // Active Flag
    FlapLike    public           flapper; // Underlying burner strategy
    FarmLike    public           farm;    // StakingRewards contract receiving the rewards
    uint256     public           burn;    // [WAD]       Burn percentage. 1 WAD = funneling 100% to the burn engine
    uint256     public           hop;     // [Seconds]   Time between kicks
    uint256     public           zzz;     // [Timestamp] Last kick

    VatLike      public immutable vat;
    UsdsJoinLike public immutable usdsJoin;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event Kick(uint256 tot, uint256 lot, uint256 pay);
    event Cage(uint256 rad);

    constructor(
        address _usdsJoin
    ) {
        usdsJoin = UsdsJoinLike(_usdsJoin);
        vat      = VatLike(usdsJoin.vat());
        
        vat.hope(_usdsJoin);
        
        hop = 1 hours; // Initial value for safety

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        live = 1;
    }

    modifier auth {
        require(wards[msg.sender] == 1, "Splitter/not-authorized");
        _;
    }

    uint256 internal constant RAY = 10 ** 27;
    uint256 internal constant RAD = 10 ** 45;

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "burn") burn = data;
        else if (what == "hop")  hop  = data;
        else revert("Splitter/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if      (what == "flapper") flapper = FlapLike(data);
        else if (what == "farm")    farm    = FarmLike(data);
        else revert("Splitter/file-unrecognized-param");
        emit File(what, data);
    }

    function kick(uint256 tot, uint256) external auth returns (uint256) {
        require(live == 1, "Splitter/not-live");

        require(block.timestamp >= zzz + hop, "Splitter/kicked-too-soon");
        zzz = block.timestamp;

        vat.move(msg.sender, address(this), tot);

        uint256 lot = tot * burn / RAD;
        if (lot > 0) {
            UsdsJoinLike(usdsJoin).exit(address(flapper), lot);
            flapper.exec(lot);
        }

        uint256 pay = (tot / RAY - lot);
        if (pay > 0) {
            UsdsJoinLike(usdsJoin).exit(address(farm), pay);
            farm.notifyRewardAmount(pay);
        }

        emit Kick(tot, lot, pay);
        return 0;
    }

    function cage(uint256) external auth {
        live = 0;
        emit Cage(0);
    }
}
