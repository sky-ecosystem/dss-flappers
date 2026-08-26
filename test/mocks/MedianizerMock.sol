// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

contract MedianizerMock {
    uint256 public price;
    mapping (address => uint256) public bud;

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function kiss(address a) external {
        bud[a] = 1;
    }

    function read() external view returns (bytes32) {
        require(bud[msg.sender] == 1, "MedianizerMock/not-authorized");
        return bytes32(price);
    }
}
