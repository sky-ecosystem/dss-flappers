pragma solidity ^0.8.21;

contract PipMock {
    uint256 value;

    function read() external view returns (uint256) {
        return value;
    }
}
