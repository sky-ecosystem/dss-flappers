pragma solidity ^0.8.21;

contract SpotterMock {
    function par() external pure returns (uint256) {
        return 10 ** 27;
    }
}
