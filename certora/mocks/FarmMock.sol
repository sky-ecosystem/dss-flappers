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

interface GemLike {
    function transfer(address, uint256) external;
}

// Minimal stand-in for the StakingRewards farm. Only the parts of the interface used by
// the Splitter, the SBEBeam and the FarmOwner are modelled, recording what was set so it
// can be asserted upon. The rewards accounting of the real farm (rewardRate, periodFinish,
// the re-rating done by setRewardsDuration, ...) is left out on purpose, as well as the
// `onlyRewardsDistribution` gate of notifyRewardAmount. The `onlyOwner` gate of the farm
// administration and the nomination handshake of its ownership transfer are kept, as the
// FarmOwner depends on them.
contract FarmMock {
    address public owner;
    address public nominatedOwner;
    address public rewardsDistribution;
    bool    public paused;
    uint256 public rewardsDuration;
    uint256 public lastReward;
    uint256 public notifications;

    function notifyRewardAmount(uint256 reward) external {
        lastReward = reward;
        notifications = 1;
    }

    function setRewardsDuration(uint256 _rewardsDuration) external {
        require(msg.sender == owner, "FarmMock/only-owner");
        rewardsDuration = _rewardsDuration;
    }

    function setRewardsDistribution(address _rewardsDistribution) external {
        require(msg.sender == owner, "FarmMock/only-owner");
        rewardsDistribution = _rewardsDistribution;
    }

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "FarmMock/only-owner");
        paused = _paused;
    }

    // The recovered tokens are sent to the owner, as the real farm does
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external {
        require(msg.sender == owner, "FarmMock/only-owner");
        GemLike(tokenAddress).transfer(owner, tokenAmount);
    }

    function nominateNewOwner(address _owner) external {
        require(msg.sender == owner, "FarmMock/only-owner");
        nominatedOwner = _owner;
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "FarmMock/not-nominated");
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }
}
