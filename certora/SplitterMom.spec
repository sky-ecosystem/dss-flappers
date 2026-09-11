// SplitterMom.spec

using Splitter as splitter;

methods {
    function owner() external returns (address) envfree;
    function authority() external returns (address) envfree;
    function splitter.wards(address) external returns (uint256) envfree;
    function splitter.hop() external returns (uint256) envfree;
    // The authority is not part of the scene, its answer is modelled by a ghost so that
    // both the `authority == 0` and the `authority != 0` branches stay reachable
    function _.canCall(address src, address dst, bytes4 sig) external => canCallGhost(src, dst) expect bool;
}

ghost canCallGhost(address, address) returns bool;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address ownerBefore = owner();
    address authorityBefore = authority();

    calldataarg args;
    f(e, args);

    address ownerAfter = owner();
    address authorityAfter = authority();

    assert ownerAfter != ownerBefore => f.selector == sig:setOwner(address).selector;
    assert authorityAfter != authorityBefore => f.selector == sig:setAuthority(address).selector;
}

// Verify correct storage changes for non reverting setOwner
rule setOwner(address usr) {
    env e;

    setOwner(e, usr);

    assert owner() == usr;
}

// Verify revert rules on setOwner
rule setOwner_revert(address usr) {
    env e;

    address owner = owner();

    setOwner@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != owner;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct storage changes for non reverting setAuthority
rule setAuthority(address usr) {
    env e;

    setAuthority(e, usr);

    assert authority() == usr;
}

// Verify revert rules on setAuthority
rule setAuthority_revert(address usr) {
    env e;

    address owner = owner();

    setAuthority@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != owner;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct splitter changes for non reverting stop
rule stop() {
    env e;

    stop(e);

    // The splitter is halted by pushing hop to the sentinel value
    assert splitter.hop() == max_uint256;
}

// Verify revert rules on stop
rule stop_revert() {
    env e;

    address owner = owner();
    address authority = authority();
    bool canCall = canCallGhost(e.msg.sender, currentContract);

    require splitter.wards(currentContract) == 1;

    stop@withrevert(e);

    bool revert1 = e.msg.value > 0;
    // isAuthorized: the mom itself and the owner always pass, anyone else needs the authority
    bool revert2 = e.msg.sender != currentContract && e.msg.sender != owner &&
                   (authority == 0 || !canCall);

    assert lastReverted <=> revert1 || revert2;
}
