// SBEBeam.spec

using Kicker as kicker;
using Splitter as splitter;
using FarmOwner as farmOwner;
using FarmMock as farm;

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function maxKbump() external returns (uint256) envfree;
    function minHop() external returns (uint256) envfree;
    function maxRate() external returns (uint256) envfree;
    function tau() external returns (uint64) envfree;
    function toc() external returns (uint128) envfree;
    function kicker.wards(address) external returns (uint256) envfree;
    function kicker.kbump() external returns (uint256) envfree;
    function kicker.khump() external returns (int256) envfree;
    function splitter.wards(address) external returns (uint256) envfree;
    function splitter.live() external returns (uint256) envfree;
    function splitter.burn() external returns (uint256) envfree;
    function splitter.hop() external returns (uint256) envfree;
    function splitter.farm() external returns (address) envfree;
    function farmOwner.wards(address) external returns (uint256) envfree;
    function farm.rewardsDuration() external returns (uint256) envfree;
    function farm.owner() external returns (address) envfree;
}

definition WAD() returns mathint = 10^18;
definition RAY() returns mathint = 10^27;
definition maxHop() returns mathint = 5 * 365 * 24 * 60 * 60; // 5 years
definition maxuint64() returns mathint = 2^64 - 1;
definition maxuint128() returns mathint = 2^128 - 1;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint maxKbumpBefore = maxKbump();
    mathint minHopBefore = minHop();
    mathint maxRateBefore = maxRate();
    mathint tauBefore = tau();
    mathint tocBefore = toc();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint maxKbumpAfter = maxKbump();
    mathint minHopAfter = minHop();
    mathint maxRateAfter = maxRate();
    mathint tauAfter = tau();
    mathint tocAfter = toc();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
    assert budsAfter != budsBefore => f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector;
    assert maxKbumpAfter != maxKbumpBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert minHopAfter != minHopBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert maxRateAfter != maxRateBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert tauAfter != tauBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert tocAfter != tocBefore => f.selector == sig:file(bytes32,uint256).selector || f.selector == sig:set(uint256,uint256,uint256).selector;
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1;
    assert wardsOtherAfter == wardsOtherBefore;
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0;
    assert wardsOtherAfter == wardsOtherBefore;
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct storage changes for non reverting kiss
rule kiss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    kiss(e, usr);

    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);

    assert budsUsrAfter == 1;
    assert budsOtherAfter == budsOtherBefore;
}

// Verify revert rules on kiss
rule kiss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    kiss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct storage changes for non reverting diss
rule diss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    diss(e, usr);

    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);

    assert budsUsrAfter == 0;
    assert budsOtherAfter == budsOtherBefore;
}

// Verify revert rules on diss
rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct storage changes for non reverting file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    mathint maxKbumpBefore = maxKbump();
    mathint minHopBefore = minHop();
    mathint maxRateBefore = maxRate();
    mathint tauBefore = tau();
    mathint tocBefore = toc();

    file(e, what, data);

    mathint maxKbumpAfter = maxKbump();
    mathint minHopAfter = minHop();
    mathint maxRateAfter = maxRate();
    mathint tauAfter = tau();
    mathint tocAfter = toc();

    assert what == to_bytes32(0x6d61784b62756d70000000000000000000000000000000000000000000000000) => maxKbumpAfter == data; // "maxKbump"
    assert what != to_bytes32(0x6d61784b62756d70000000000000000000000000000000000000000000000000) => maxKbumpAfter == maxKbumpBefore;
    assert what == to_bytes32(0x6d696e486f700000000000000000000000000000000000000000000000000000) => minHopAfter == data; // "minHop"
    assert what != to_bytes32(0x6d696e486f700000000000000000000000000000000000000000000000000000) => minHopAfter == minHopBefore;
    assert what == to_bytes32(0x6d61785261746500000000000000000000000000000000000000000000000000) => maxRateAfter == data; // "maxRate"
    assert what != to_bytes32(0x6d61785261746500000000000000000000000000000000000000000000000000) => maxRateAfter == maxRateBefore;
    assert what == to_bytes32(0x7461750000000000000000000000000000000000000000000000000000000000) => tauAfter == data; // "tau"
    assert what != to_bytes32(0x7461750000000000000000000000000000000000000000000000000000000000) => tauAfter == tauBefore;
    assert what == to_bytes32(0x746f630000000000000000000000000000000000000000000000000000000000) => tocAfter == data; // "toc"
    assert what != to_bytes32(0x746f630000000000000000000000000000000000000000000000000000000000) => tocAfter == tocBefore;
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6d61784b62756d70000000000000000000000000000000000000000000000000) && // "maxKbump"
                   what != to_bytes32(0x6d696e486f700000000000000000000000000000000000000000000000000000) && // "minHop"
                   what != to_bytes32(0x6d61785261746500000000000000000000000000000000000000000000000000) && // "maxRate"
                   what != to_bytes32(0x7461750000000000000000000000000000000000000000000000000000000000) && // "tau"
                   what != to_bytes32(0x746f630000000000000000000000000000000000000000000000000000000000);   // "toc"
    bool revert4 = what == to_bytes32(0x6d696e486f700000000000000000000000000000000000000000000000000000) && data < 300;
    bool revert5 = what == to_bytes32(0x7461750000000000000000000000000000000000000000000000000000000000) && data > maxuint64();
    bool revert6 = what == to_bytes32(0x746f630000000000000000000000000000000000000000000000000000000000) && data > maxuint128();

    assert lastReverted <=> revert1 || revert2 || revert3 || revert4 || revert5 || revert6;
}

// Verify correct storage changes for non reverting set
rule set(uint256 kbump, uint256 burn, uint256 hop) {
    env e;

    require e.block.timestamp <= max_uint128;

    mathint farmRewardsDurationBefore = farm.rewardsDuration();

    set(e, kbump, burn, hop);

    assert toc() == e.block.timestamp;
    assert kicker.kbump() == kbump;
    assert splitter.burn() == burn;
    assert splitter.hop() == hop;
    // The farm duration is only synced when there is a reward stream to re-rate
    assert burn < WAD() => farm.rewardsDuration() == hop;
    assert burn == WAD() => farm.rewardsDuration() == farmRewardsDurationBefore;
    // The bounds hold on the values that were set
    assert kicker.kbump() <= maxKbump();
    assert kicker.kbump() % RAY() == 0;
    assert splitter.burn() <= WAD();
    assert splitter.hop() >= minHop();
    assert splitter.hop() <= maxHop();
    assert kicker.kbump() / splitter.hop() <= maxRate();
}

// Verify revert rules on set
rule set_revert(uint256 kbump, uint256 burn, uint256 hop) {
    env e;

    mathint budsSender = buds(e.msg.sender);
    mathint maxKbump = maxKbump();
    mathint minHop = minHop();
    mathint maxRate = maxRate();
    mathint tau = tau();
    mathint toc = toc();

    mathint splitterLive = splitter.live();
    mathint splitterHop = splitter.hop();
    mathint kickerWardsBeam = kicker.wards(currentContract);
    mathint splitterWardsBeam = splitter.wards(currentContract);
    mathint farmOwnerWardsBeam = farmOwner.wards(currentContract);
    address splitterFarm = splitter.farm();
    mathint farmRewardsDuration = farm.rewardsDuration();

    set@withrevert(e, kbump, burn, hop);

    bool revert1  = e.msg.value > 0;
    bool revert2  = budsSender != 1;
    bool revert3  = splitterLive != 1;
    bool revert4  = splitterHop == max_uint256;
    bool revert5  = tau + toc > maxuint128();
    bool revert6  = e.block.timestamp < tau + toc;
    bool revert7  = kbump > maxKbump;
    bool revert8  = kbump % RAY() != 0;
    bool revert9  = burn > WAD();
    bool revert10 = hop < minHop;
    bool revert11 = hop > maxHop();
    bool revert12 = hop == 0; // division by zero on kbump / hop
    bool revert13 = hop != 0 && kbump / hop > maxRate;
    // kicker.file("kbump", kbump) and splitter.file("burn"/"hop", ...)
    bool revert14 = kickerWardsBeam != 1;
    bool revert15 = splitterWardsBeam != 1;
    // farm sync
    bool revert16 = burn < WAD() && splitterFarm == 0;
    bool revert17 = burn < WAD() && farmRewardsDuration != hop && farmOwnerWardsBeam != 1;

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15 ||
                            revert16 || revert17;
}
