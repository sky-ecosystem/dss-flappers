// FlapperUniV2SwapOnly.spec

using Usds as usds;
using Sky as sky;
using SpotterMock as spotter;
using PipMock as pip;
using UniswapV2Pair as pair;

methods {
    function wards(address) external returns (uint256) envfree;
    function pip() external returns (address) envfree;
    function want() external returns (uint256) envfree;
    function receiver() external returns (address) envfree;
    function usdsFirst() external returns (bool) envfree;
    function usds.balanceOf(address) external returns (uint256) envfree;
    function usds.totalSupply() external returns (uint256) envfree;
    function sky.balanceOf(address) external returns (uint256) envfree;
    function sky.totalSupply() external returns (uint256) envfree;
    function pip.read() external returns (uint256) envfree;
    function spotter.par() external returns (uint256) envfree;
    function pair.getReserves() external returns (uint112, uint112, uint32) envfree;
    function pair.unlocked() external returns (uint256) envfree;
    function _.uniswapV2Call(address, uint256, uint256, bytes) external => NONDET;
}

definition RAY() returns mathint = 10^27;
definition maxuint112() returns mathint = 2^112 - 1;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    address pipBefore = pip();
    mathint wantBefore = want();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address pipAfter = pip();
    mathint wantAfter = want();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
    assert pipAfter != pipBefore => f.selector == sig:file(bytes32,address).selector;
    assert wantAfter != wantBefore => f.selector == sig:file(bytes32,uint256).selector;
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

    mathint wantAfter = want();

    assert wantAfter == data;
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x77616e7400000000000000000000000000000000000000000000000000000000); // "want"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

// Verify correct storage changes for non reverting file
rule file_address(bytes32 what, address data) {
    env e;

    file(e, what, data);

    address pipAfter = pip();

    assert pipAfter == data;
}

// Verify revert rules on file
rule file_address_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x7069700000000000000000000000000000000000000000000000000000000000); // "pip"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

definition getAmountOut(mathint amtIn, mathint reserveIn, mathint reserveOut) returns mathint =
    amtIn * 997 * reserveOut / (reserveIn * 1000 + amtIn * 997);

// Verify correct balance changes for non reverting exec
rule exec(uint256 lot) {
    env e;

    require usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)

    address receiver = receiver();

    // Note - `_getReserves` uses the stored reserves, which can be behind the balances
    mathint reserveUsds; mathint reserveGem; mathint b;
    reserveUsds, reserveGem, b = pair.getReserves();
    require reserveUsds > 0 && reserveGem > 0;

    mathint usdsBalanceOfPairBefore = usds.balanceOf(pair);
    mathint usdsBalanceOfFlapperBefore = usds.balanceOf(currentContract);
    mathint skyBalanceOfPairBefore  = sky.balanceOf(pair);
    mathint skyBalanceOfReceiverBefore = sky.balanceOf(receiver);
    // Token invariant - usds credits the balance unchecked, relying on the sum of the
    // balances being the total supply
    require usds.totalSupply() >= usdsBalanceOfPairBefore + usdsBalanceOfFlapperBefore;
    require sky.totalSupply() >= skyBalanceOfPairBefore + skyBalanceOfReceiverBefore;

    mathint buy = getAmountOut(lot, reserveUsds, reserveGem);

    exec(e, lot);

    mathint usdsBalanceOfPairAfter = usds.balanceOf(pair);
    mathint usdsBalanceOfFlapperAfter = usds.balanceOf(currentContract);
    mathint skyBalanceOfPairAfter  = sky.balanceOf(pair);
    mathint skyBalanceOfReceiverAfter = sky.balanceOf(receiver);

    assert buy < reserveGem;
    assert usdsBalanceOfPairAfter == usdsBalanceOfPairBefore + lot;
    assert usdsBalanceOfFlapperAfter == usdsBalanceOfFlapperBefore - lot;
    assert receiver != pair => skyBalanceOfPairAfter == skyBalanceOfPairBefore - buy;
    assert receiver != pair => skyBalanceOfReceiverAfter == skyBalanceOfReceiverBefore + buy;
    assert receiver == pair => skyBalanceOfReceiverAfter == skyBalanceOfReceiverBefore;
}

// Verify revert rules on exec
rule exec_revert(uint256 lot) {
    env e;

    require usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)
    require pair.unlocked() == 1;

    address receiver = receiver();
    require receiver != 0;

    mathint wardsSender = wards(e.msg.sender);
    mathint want = want();

    mathint reserveUsds; mathint reserveGem; mathint b;
    reserveUsds, reserveGem, b = pair.getReserves();
    require reserveUsds > 0 && reserveGem > 0;

    mathint usdsBalanceOfPair = usds.balanceOf(pair);
    mathint skyBalanceOfPair  = sky.balanceOf(pair);
    mathint usdsBalanceOfFlapper = usds.balanceOf(currentContract);
    mathint skyBalanceOfReceiver = sky.balanceOf(receiver);
    require usdsBalanceOfPair >= reserveUsds;
    require skyBalanceOfPair  >= reserveGem;
    // Token invariants, so the transfers can not overflow a balance
    require usds.totalSupply() >= usdsBalanceOfPair + usdsBalanceOfFlapper;
    require receiver != pair => sky.totalSupply() >= skyBalanceOfPair + skyBalanceOfReceiver;

    mathint buy = getAmountOut(lot, reserveUsds, reserveGem);

    mathint price = pip.read();
    mathint par = spotter.par();
    require par > 0;

    exec@withrevert(e, lot);

    // auth
    bool revert1  = e.msg.value > 0;
    bool revert2  = wardsSender != 1;
    // _getAmountOut
    bool revert3  = lot * 997 > max_uint256;
    bool revert4  = lot * 997 * reserveGem > max_uint256;
    bool revert5  = reserveUsds * 1000 + lot * 997 > max_uint256;
    // want check
    bool revert6  = price * RAY() > max_uint256;
    bool revert7  = price * RAY() / par == 0;
    bool revert8  = lot * want > max_uint256;
    bool revert9  = !revert7 && buy < lot * want / (price * RAY() / par);
    // usds transfer of lot
    bool revert10 = usdsBalanceOfFlapper < lot;
    // swap
    bool revert11 = buy == 0;
    bool revert12 = buy >= reserveGem;
    bool revert13 = receiver == usds || receiver == sky;
    bool revert14 = usdsBalanceOfPair + lot > maxuint112() ||
                    skyBalanceOfPair - (receiver != pair ? buy : 0) > maxuint112();

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14;
}
