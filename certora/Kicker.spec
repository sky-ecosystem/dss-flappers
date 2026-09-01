// Kicker.spec

using Vat as vat;
using SplitterMock as splitter;

methods {
    function wards(address) external returns (uint256) envfree;
    function kbump() external returns (uint256) envfree;
    function khump() external returns (int256) envfree;
    function vow() external returns (address) envfree;
    function vat.wards(address) external returns (uint256) envfree;
    function vat.can(address, address) external returns (uint256) envfree;
    function vat.dai(address) external returns (uint256) envfree;
    function vat.sin(address) external returns (uint256) envfree;
    function vat.debt() external returns (uint256) envfree;
    function vat.vice() external returns (uint256) envfree;
    function splitter.wards(address) external returns (uint256) envfree;
    function splitter.live() external returns (uint256) envfree;
    function splitter.hop() external returns (uint256) envfree;
    function splitter.zzz() external returns (uint256) envfree;
    function splitter.lastTot() external returns (uint256) envfree;
}

definition maxint256() returns mathint = 2^255 - 1;
definition minint256() returns mathint = -2^255;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint kbumpBefore = kbump();
    mathint khumpBefore = khump();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint kbumpAfter = kbump();
    mathint khumpAfter = khump();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
    assert kbumpAfter != kbumpBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert khumpAfter != khumpBefore => f.selector == sig:file(bytes32,int256).selector;
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

// Verify correct storage changes for non reverting file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    file(e, what, data);

    mathint kbumpAfter = kbump();

    assert kbumpAfter == data;
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6b62756d70000000000000000000000000000000000000000000000000000000); // "kbump"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

// Verify correct storage changes for non reverting file
rule file_int256(bytes32 what, int256 data) {
    env e;

    file(e, what, data);

    mathint khumpAfter = khump();

    assert khumpAfter == data;
}

// Verify revert rules on file
rule file_int256_revert(bytes32 what, int256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6b68756d70000000000000000000000000000000000000000000000000000000); // "khump"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

// Verify correct storage changes for non reverting flap
rule flap() {
    env e;

    address vow = vow();
    // The vow is only the sin bearer, it is not part of the surplus route
    require vow != currentContract;
    require vow != splitter;

    mathint kbump = kbump();

    mathint vatDaiVowBefore = vat.dai(vow);
    mathint vatSinVowBefore = vat.sin(vow);
    mathint vatDaiKickerBefore = vat.dai(currentContract);
    mathint vatDaiSplitterBefore = vat.dai(splitter);
    mathint vatDebtBefore = vat.debt();
    mathint vatViceBefore = vat.vice();

    mathint id = flap(e);

    mathint vatDaiVowAfter = vat.dai(vow);
    mathint vatSinVowAfter = vat.sin(vow);
    mathint vatDaiKickerAfter = vat.dai(currentContract);
    mathint vatDaiSplitterAfter = vat.dai(splitter);
    mathint vatDebtAfter = vat.debt();
    mathint vatViceAfter = vat.vice();

    assert id == 0;
    // The surplus is minted against the vow's sin
    assert vatSinVowAfter == vatSinVowBefore + kbump;
    assert vatDaiVowAfter == vatDaiVowBefore;
    assert vatDebtAfter == vatDebtBefore + kbump;
    assert vatViceAfter == vatViceBefore + kbump;
    // and handed over to the splitter in full, nothing is left behind in the kicker
    assert vatDaiKickerAfter == vatDaiKickerBefore;
    assert vatDaiSplitterAfter == vatDaiSplitterBefore + kbump;
    assert splitter.lastTot() == kbump;
    assert splitter.zzz() == e.block.timestamp;
}

// Verify revert rules on flap
rule flap_revert() {
    env e;

    address vow = vow();
    require vow != currentContract;
    require vow != splitter;

    mathint kbump = kbump();
    mathint khump = khump();

    mathint vatWardsKicker = vat.wards(currentContract);
    mathint vatCanKickerSplitter = vat.can(currentContract, splitter);
    mathint splitterWardsKicker = splitter.wards(currentContract);
    mathint splitterLive = splitter.live();
    mathint splitterZzz = splitter.zzz();
    mathint splitterHop = splitter.hop();

    mathint vatDaiVow = vat.dai(vow);
    mathint vatSinVow = vat.sin(vow);
    mathint vatDaiKicker = vat.dai(currentContract);
    mathint vatDaiSplitter = vat.dai(splitter);
    mathint vatDebt = vat.debt();
    mathint vatVice = vat.vice();

    flap@withrevert(e);

    // _toInt256 and the flap threshold
    bool revert1  = e.msg.value > 0;
    bool revert2  = vatDaiVow > maxint256();
    bool revert3  = vatSinVow > maxint256();
    bool revert4  = kbump > maxint256();
    bool revert5  = vatSinVow + kbump > maxint256();
    bool revert6  = vatSinVow + kbump + khump > maxint256();
    bool revert7  = vatSinVow + kbump + khump < minint256();
    bool revert8  = vatDaiVow < vatSinVow + kbump + khump;
    // vat.suck(vow, kicker, kbump)
    bool revert9  = vatWardsKicker != 1;
    bool revert10 = vatSinVow + kbump > max_uint256;
    bool revert11 = vatDaiKicker + kbump > max_uint256;
    bool revert12 = vatVice + kbump > max_uint256;
    bool revert13 = vatDebt + kbump > max_uint256;
    // splitter.kick(kbump, 0)
    bool revert14 = splitterWardsKicker != 1;
    bool revert15 = splitterLive != 1;
    bool revert16 = splitterZzz + splitterHop > max_uint256;
    bool revert17 = e.block.timestamp < splitterZzz + splitterHop;
    // vat.move(kicker, splitter, kbump) - the kicker was just credited kbump
    bool revert18 = vatCanKickerSplitter != 1;
    bool revert19 = vatDaiSplitter + kbump > max_uint256;

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15 ||
                            revert16 || revert17 || revert18 ||
                            revert19;
}
