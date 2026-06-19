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

import "dss-test/DssTest.sol";

import { FarmOwner } from "src/FarmOwner.sol";

import { GemMock } from "test/mocks/GemMock.sol";

contract FarmMock {
    uint256 public rewardsDuration;
    address public rewardsDistribution;
    address public recoveredToken;
    uint256 public recoveredAmount;
    bool    public paused;
    address public nominatedOwner;
    address public owner;
    uint256 public acceptOwnershipCalls;

    function setRewardsDuration(uint256 _rewardsDuration) external {
        rewardsDuration = _rewardsDuration;
    }

    function setRewardsDistribution(address _rewardsDistribution) external {
        rewardsDistribution = _rewardsDistribution;
    }

    // Mirrors Synthetix StakingRewards: recovered tokens are sent to the owner,
    // which in this deployment is the FarmOwner contract calling in (msg.sender).
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external {
        recoveredToken  = tokenAddress;
        recoveredAmount = tokenAmount;
        GemMock(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    function setPaused(bool _paused) external {
        paused = _paused;
    }

    function nominateNewOwner(address _nominatedOwner) external {
        nominatedOwner = _nominatedOwner;
    }

    function acceptOwnership() external {
        acceptOwnershipCalls += 1;
        owner = msg.sender;
    }
}

contract FarmOwnerTest is DssTest {
    FarmMock  farm;
    FarmOwner owner;

    function setUp() public {
        farm  = new FarmMock();
        owner = new FarmOwner(address(farm));
    }

    // --- constructor / admin ---

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        FarmOwner fo = new FarmOwner(address(farm));

        assertEq(address(fo.farm()), address(farm));
        assertEq(fo.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(owner), "FarmOwner");
    }

    function testAuthModifiers() public {
        owner.deny(address(this));
        checkModifier(address(owner), "FarmOwner/not-authorized", [
            FarmOwner.setRewardsDuration.selector,
            FarmOwner.setRewardsDistribution.selector,
            FarmOwner.recoverERC20.selector,
            FarmOwner.setPaused.selector,
            FarmOwner.nominateNewOwner.selector,
            FarmOwner.acceptOwnership.selector
        ]);
    }

    // --- forwarded onlyOwner methods ---

    function testSetRewardsDurationForwards() public {
        owner.setRewardsDuration(7 days);
        assertEq(farm.rewardsDuration(), 7 days);
    }

    function testSetRewardsDistributionForwards() public {
        owner.setRewardsDistribution(address(0xBEEF));
        assertEq(farm.rewardsDistribution(), address(0xBEEF));
    }

    function testRecoverERC20Forwards() public {
        GemMock gem = new GemMock(0);
        gem.mint(address(farm), 1_234);

        assertEq(gem.balanceOf(address(farm)), 1_234);
        assertEq(gem.balanceOf(address(owner)), 0);
        assertEq(gem.balanceOf(address(0xBEEF)), 0);

        owner.recoverERC20(address(gem), address(0xBEEF), 1_234);

        assertEq(farm.recoveredToken(),  address(gem));
        assertEq(farm.recoveredAmount(), 1_234);

        // Tokens must end up with the recipient, not stranded in the farm or FarmOwner.
        assertEq(gem.balanceOf(address(farm)), 0);
        assertEq(gem.balanceOf(address(owner)), 0);
        assertEq(gem.balanceOf(address(0xBEEF)), 1_234);
    }

    function testSetPausedForwards() public {
        owner.setPaused(true);
        assertTrue(farm.paused());

        owner.setPaused(false);
        assertFalse(farm.paused());
    }

    function testNominateNewOwnerForwards() public {
        owner.nominateNewOwner(address(0xCAFE));
        assertEq(farm.nominatedOwner(), address(0xCAFE));
    }

    function testAcceptOwnershipForwards() public {
        owner.acceptOwnership();
        assertEq(farm.acceptOwnershipCalls(), 1);
        assertEq(farm.owner(), address(owner));
    }
}
