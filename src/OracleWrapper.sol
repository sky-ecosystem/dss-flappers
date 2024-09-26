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

interface PipLike {
    function read() external view returns (bytes32);
}

contract OracleWrapper {

    PipLike public immutable pip;
    address public immutable flapper;
    uint256 public immutable divisor; // Assumes divisor << WAD

    constructor(
        address _pip,
        address _flapper,
        uint256 _divisor
    ) {
        pip     = PipLike(_pip);
        flapper = _flapper;
        divisor = _divisor;
    }

    function read() external view returns (bytes32) {
        require(msg.sender == flapper, "OracleWrapper/unauthorized-reader"); // preserve oracles whitelisting
        return bytes32(uint256(pip.read()) / divisor);
    }
}
