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

interface SplitterLike {
    function file(bytes32, uint256) external;
}

interface AuthorityLike {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
}

// Bypass governance delay to disable the splitter
contract SplitterMom {
    address public owner;
    address public authority;

    SplitterLike public immutable splitter;

    event SetOwner(address indexed _owner);
    event SetAuthority(address indexed _authority);
    event Stop();

    modifier onlyOwner {
        require(msg.sender == owner, "SplitterMom/only-owner");
        _;
    }

    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "SplitterMom/not-authorized");
        _;
    }

    constructor(address _splitter) {
        splitter = SplitterLike(_splitter);
        
        owner = msg.sender;
        emit SetOwner(msg.sender);
    }

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == address(0)) {
            return false;
        } else {
            return AuthorityLike(authority).canCall(src, address(this), sig);
        }
    }

    // Governance actions with delay
    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
        emit SetOwner(_owner);
    }

    function setAuthority(address _authority) external onlyOwner {
        authority = _authority;
        emit SetAuthority(_authority);
    }

    // Governance action without delay
    function stop() external auth {
        splitter.file("hop", type(uint256).max);
        emit Stop();
    }
}
