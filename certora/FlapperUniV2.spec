// FlapperUniV2.spec

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
    function pair.balanceOf(address) external returns (uint256) envfree;
    function pair.getReserves() external returns (uint112, uint112, uint32) envfree;
    function pair.totalSupply() external returns (uint256) envfree;
    function pair.unlocked() external returns (uint256) envfree;
    function pair.MINIMUM_LIQUIDITY() external returns (uint256) envfree;
    function _.uniswapV2Call(address, uint256, uint256, bytes) external => NONDET;
    // Babylonian.sqrt is a fixed amount (7) of Newton iterations. It is replaced here by its
    // specification, the floor of the square root, which keeps all the arithmetic of
    // `_getUsdsToSell` (and therefore its overflow behaviour) intact.
    function Babylonian.sqrt(uint256 x) internal returns (uint256) => sqrtSummary(x);
}

persistent ghost bool sqrtCalled;

persistent ghost sqrtGhost(mathint) returns mathint {
    axiom forall mathint x. x >= 0 => sqrtGhost(x) >= 0                &&
                                     sqrtGhost(x) * sqrtGhost(x) <= x &&
                                     (sqrtGhost(x) + 1) * (sqrtGhost(x) + 1) > x;
}

function sqrtSummary(uint256 x) returns uint256 {
    sqrtCalled = true;
    return require_uint256(sqrtGhost(to_mathint(x))); // sqrt(uint256) always fits in uint256
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

definition getUsdsToSell(mathint lot, mathint reserveUsds) returns mathint =
    (sqrtGhost(reserveUsds * (lot * 3988000 + reserveUsds * 3988009)) - reserveUsds * 1997) / 1994;
definition getAmountOut(mathint amtIn, mathint reserveIn, mathint reserveOut) returns mathint =
    amtIn * 997 * reserveOut / (reserveIn * 1000 + amtIn * 997);
definition mathMin(mathint x, mathint y) returns mathint = x < y ? x : y;
definition getLiquidity(mathint amt0, mathint amt1, mathint reserve0, mathint reserve1, mathint totalSupply) returns mathint =
    mathMin(amt0 * totalSupply / reserve0, amt1 * totalSupply / reserve1);

// Verify correct balance changes for non reverting exec
rule exec(uint256 lot) {
    env e;

    require usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)
    require !sqrtCalled;

    address receiver = receiver();

    mathint reserveUsdsBefore; mathint reserveGemBefore; mathint b;
    reserveUsdsBefore, reserveGemBefore, b = pair.getReserves();
    mathint usdsBalanceOfPairBefore = usds.balanceOf(pair);
    mathint skyBalanceOfPairBefore  = sky.balanceOf(pair);
    // Reserves are in sync with the balances, so `_getReserves` does not call `sync`
    require usdsBalanceOfPairBefore == reserveUsdsBefore;
    require skyBalanceOfPairBefore  == reserveGemBefore;
    require reserveUsdsBefore > 0 && reserveGemBefore > 0;

    mathint usdsBalanceOfFlapperBefore = usds.balanceOf(currentContract);
    mathint skyBalanceOfFlapperBefore  = sky.balanceOf(currentContract);
    // Token invariant - usds credits the balance unchecked, relying on the sum of the
    // balances being the total supply
    require usds.totalSupply() >= usdsBalanceOfPairBefore + usdsBalanceOfFlapperBefore;
    mathint pairBalanceOfReceiverBefore = pair.balanceOf(receiver);
    mathint pairTotalSupplyBefore = pair.totalSupply();
    require pairTotalSupplyBefore >= pair.MINIMUM_LIQUIDITY();
    require pairTotalSupplyBefore >= pairBalanceOfReceiverBefore;

    mathint sell = getUsdsToSell(lot, reserveUsdsBefore);
    mathint buy  = getAmountOut(sell, reserveUsdsBefore, reserveGemBefore);

    exec(e, lot);

    mathint reserveUsdsAfter; mathint reserveGemAfter;
    reserveUsdsAfter, reserveGemAfter, b = pair.getReserves();
    mathint usdsBalanceOfPairAfter = usds.balanceOf(pair);
    mathint skyBalanceOfPairAfter  = sky.balanceOf(pair);
    mathint usdsBalanceOfFlapperAfter = usds.balanceOf(currentContract);
    mathint skyBalanceOfFlapperAfter  = sky.balanceOf(currentContract);
    mathint pairBalanceOfReceiverAfter = pair.balanceOf(receiver);

    assert sqrtCalled;
    assert sell <= lot;
    assert buy < reserveGemBefore;
    assert usdsBalanceOfFlapperAfter == usdsBalanceOfFlapperBefore - lot;
    assert skyBalanceOfFlapperAfter == skyBalanceOfFlapperBefore;
    assert usdsBalanceOfPairAfter == usdsBalanceOfPairBefore + lot;
    assert skyBalanceOfPairAfter == skyBalanceOfPairBefore;
    assert reserveUsdsAfter == usdsBalanceOfPairAfter;
    assert reserveGemAfter == skyBalanceOfPairAfter;
    assert pairBalanceOfReceiverAfter > pairBalanceOfReceiverBefore;
    assert pairBalanceOfReceiverAfter - pairBalanceOfReceiverBefore ==
           getLiquidity(lot - sell, buy, reserveUsdsBefore + sell, reserveGemBefore - buy, pairTotalSupplyBefore);
}

// Verify revert rules on exec
rule exec_revert(uint256 lot) {
    env e;

    require usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)
    require pair.unlocked() == 1;

    address receiver = receiver();

    mathint wardsSender = wards(e.msg.sender);
    mathint want = want();

    mathint reserveUsds; mathint reserveGem; mathint b;
    reserveUsds, reserveGem, b = pair.getReserves();
    // `_getReserves` syncs the reserves to the balances if they are behind, so the
    // effective reserves used by exec are the balances of the pair
    mathint usdsBalanceOfPair = usds.balanceOf(pair);
    mathint skyBalanceOfPair  = sky.balanceOf(pair);
    require usdsBalanceOfPair >= reserveUsds;
    require skyBalanceOfPair  >= reserveGem;
    require usdsBalanceOfPair > 0 && skyBalanceOfPair > 0;

    mathint usdsBalanceOfFlapper = usds.balanceOf(currentContract);
    mathint skyBalanceOfFlapper  = sky.balanceOf(currentContract);
    // Token invariants, so the transfers can not overflow a balance
    require usdsBalanceOfPair + usdsBalanceOfFlapper <= usds.totalSupply();
    require skyBalanceOfPair + skyBalanceOfFlapper <= sky.totalSupply();

    mathint pairBalanceOfReceiver = pair.balanceOf(receiver);
    mathint pairTotalSupply = pair.totalSupply();
    require pairTotalSupply > 0;
    require pairTotalSupply >= pairBalanceOfReceiver;

    mathint sqrtArg = usdsBalanceOfPair * (lot * 3988000 + usdsBalanceOfPair * 3988009);
    mathint sell = getUsdsToSell(lot, usdsBalanceOfPair);
    mathint buy  = getAmountOut(sell, usdsBalanceOfPair, skyBalanceOfPair);
    mathint liquidity = getLiquidity(lot - sell, buy, usdsBalanceOfPair + sell, skyBalanceOfPair - buy, pairTotalSupply);

    mathint price = pip.read();
    mathint par = spotter.par();
    require par > 0;

    exec@withrevert(e, lot);

    // auth
    bool revert1  = e.msg.value > 0;
    bool revert2  = wardsSender != 1;
    // _getReserves (sync)
    bool revert3  = usdsBalanceOfPair > maxuint112() || skyBalanceOfPair > maxuint112();
    // _getUsdsToSell
    bool revert4  = lot * 3988000 > max_uint256;
    bool revert5  = lot * 3988000 + usdsBalanceOfPair * 3988009 > max_uint256;
    bool revert6  = sqrtArg > max_uint256;
    bool revert7  = sqrtGhost(sqrtArg) < usdsBalanceOfPair * 1997;
    // _getAmountOut
    bool revert8  = sell * 997 > max_uint256 || sell * 997 * skyBalanceOfPair > max_uint256;
    bool revert9  = usdsBalanceOfPair * 1000 + sell * 997 > max_uint256;
    // want check
    bool revert10 = price * RAY() > max_uint256;
    bool revert11 = price * RAY() / par == 0;
    bool revert12 = sell * want > max_uint256;
    bool revert13 = !revert11 && buy < sell * want / (price * RAY() / par);
    // usds transfer of sell
    bool revert14 = usdsBalanceOfFlapper < sell;
    // swap
    bool revert15 = buy == 0;
    bool revert16 = buy >= skyBalanceOfPair;
    bool revert17 = sell == 0;
    bool revert18 = usdsBalanceOfPair + sell > maxuint112();
    // usds transfer of lot - sell
    bool revert19 = sell > lot;
    bool revert20 = usdsBalanceOfFlapper < lot;
    // mint
    bool revert21 = (lot - sell) * pairTotalSupply > max_uint256;
    bool revert22 = buy * pairTotalSupply > max_uint256;
    bool revert23 = !revert16 && liquidity == 0;
    bool revert24 = !revert16 && pairTotalSupply + liquidity > max_uint256;
    bool revert25 = usdsBalanceOfPair + lot > maxuint112();

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15 ||
                            revert16 || revert17 || revert18 ||
                            revert19 || revert20 || revert21 ||
                            revert22 || revert23 || revert24 ||
                            revert25;
}
