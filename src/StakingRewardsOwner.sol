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

interface FarmLike {
    function setRewardsDuration(uint256) external;
    function setRewardsDistribution(address) external;
    function recoverERC20(address, uint256) external;
    function setPaused(bool) external;
    function nominateNewOwner(address) external;
    function acceptOwnership() external;
}

// StakingRewardsOwner holds ownership of an external Synthetix-style StakingRewards farm
// on behalf of governance. Every `onlyOwner` method on the farm is exposed as a
// ward-gated forwarder so wards (typically MCD_PAUSE_PROXY and the SBEBeam)
// retain full farm administration while the farm's single-owner slot is held
// by this contract.
contract StakingRewardsOwner {
    // --- storage variables ---

    mapping(address => uint256) public wards;

    // --- immutables ---

    FarmLike public immutable farm;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    // --- modifiers ---

    modifier auth {
        require(wards[msg.sender] == 1, "StakingRewardsOwner/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(address _farm) {
        farm = FarmLike(_farm);

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

    // --- forwarded onlyOwner methods ---

    function setRewardsDuration(uint256 duration) external auth {
        farm.setRewardsDuration(duration);
    }

    function setRewardsDistribution(address rewardsDistribution) external auth {
        farm.setRewardsDistribution(rewardsDistribution);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external auth {
        farm.recoverERC20(tokenAddress, tokenAmount);
    }

    function setPaused(bool paused) external auth {
        farm.setPaused(paused);
    }

    function nominateNewOwner(address usr) external auth {
        farm.nominateNewOwner(usr);
    }

    function acceptOwnership() external auth {
        farm.acceptOwnership();
    }
}
