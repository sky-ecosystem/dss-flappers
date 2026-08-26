// OracleWrapper.spec

using PipMock as pip;

methods {
    function pip() external returns (address) envfree;
    function flapper() external returns (address) envfree;
    function divisor() external returns (uint256) envfree;
    function pip.read() external returns (uint256) envfree;
}

// Verify correct value returned by non reverting read
rule read() {
    env e;

    address flapper = flapper();
    mathint price = pip.read();
    mathint divisor = divisor();

    bytes32 value = read(e);

    assert e.msg.sender == flapper;
    assert value == to_bytes32(require_uint256(price / divisor));
}

// Verify revert rules on read
rule read_revert() {
    env e;

    address flapper = flapper();
    mathint divisor = divisor();

    read@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != flapper;
    bool revert3 = divisor == 0;

    assert lastReverted <=> revert1 || revert2 || revert3;
}
