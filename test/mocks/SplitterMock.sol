// SPDX-License-Identifier: AGPL-3.0-or-later

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
}

contract SplitterMock {
    FlapLike    public           flapper;

    VatLike      public immutable vat;
    UsdsJoinLike public immutable usdsJoin;

    constructor(
        address _usdsJoin
    ) {
        usdsJoin = UsdsJoinLike(_usdsJoin);
        vat = VatLike(usdsJoin.vat());

        vat.hope(_usdsJoin);
    }

    uint256 internal constant RAY = 10 ** 27;

    function file(bytes32 what, address data) external {
        if (what == "flapper") flapper = FlapLike(data);
        else revert("SplitterMock/file-unrecognized-param");
    }

    function kick(uint256 tot, uint256) external returns (uint256) {
        vat.move(msg.sender, address(this), tot);
        uint256 lot = tot / RAY;
        UsdsJoinLike(usdsJoin).exit(address(flapper), lot);
        flapper.exec(lot);
        return 0;
    }
}
