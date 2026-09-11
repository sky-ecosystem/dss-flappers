pragma solidity ^0.8.21;

contract UniswapV2FactoryMock {
    function feeTo() external pure returns (address) {
        return address(0);
    }
}
