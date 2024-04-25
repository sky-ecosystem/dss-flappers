// FlapperUniV2.spec

using Vat as vat;
using DaiJoin as daiJoin;
using Dai as dai;
using DSToken as mkr;
using SpotterMock as spotter;
using PipMock as pip;
using UniswapV2Pair as pair;
using Auxiliar as aux;

methods {
    function wards(address) external returns (uint256) envfree;
    function live() external returns (uint256) envfree;
    function pip() external returns (address) envfree;
    function hop() external returns (uint256) envfree;
    function zzz() external returns (uint256) envfree;
    function want() external returns (uint256) envfree => ALWAYS(980000000000000000); // 0.98 * 10^18;
    function pip() external returns (address) envfree;
    function vat() external returns (address) envfree;
    function daiJoin() external returns (address) envfree;
    function spotter() external returns (address) envfree;
    function dai() external returns (address) envfree;
    function gem() external returns (address) envfree;
    function receiver() external returns (address) envfree;
    function pair() external returns (address) envfree;
    function daiFirst() external returns (bool) envfree;
    function vat.can(address, address) external returns (uint256) envfree;
    function vat.dai(address) external returns (uint256) envfree;
    function dai.balanceOf(address) external returns (uint256) envfree;
    function mkr.balanceOf(address) external returns (uint256) envfree;
    function pip.read() external returns (uint256) envfree;
    function spotter.par() external returns (uint256) envfree => ALWAYS(1000000000000000000000000000); // 10^27
    function pair.balanceOf(address) external returns (uint256) envfree;
    function pair.getReserves() external returns (uint112, uint112, uint32) envfree;
    function pair.totalSupply() external returns (uint256) envfree;
    function pair.unlocked() external returns (uint256) envfree;
    function _.uniswapV2Call(address , uint , uint , bytes) external => NONDET;
    function UniswapV2Pair.sync() external => NONDET;
    function UniswapV2Pair.MINIMUM_LIQUIDITY() external returns (uint256) envfree;
    function aux.sqrt(uint256) external returns (uint256) envfree;
}

definition WAD() returns mathint = 10^18;
definition RAY() returns mathint = 10^27;
definition maxuint112() returns mathint = 2^112 - 1;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;
    bytes32 anyBytes32;

    mathint wardsBefore = wards(anyAddr);
    mathint liveBefore = live();
    address pipBefore = pip();
    mathint hopBefore = hop();
    mathint zzzBefore = zzz();
    mathint wantBefore = want();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint liveAfter = live();
    address pipAfter = pip();
    mathint hopAfter = hop();
    mathint zzzAfter = zzz();
    mathint wantAfter = want();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert liveAfter != liveBefore => f.selector == sig:cage(uint256).selector, "live changed in an unexpected function";
    assert pipAfter != pipBefore => f.selector == sig:file(bytes32,address).selector, "pip changed in an unexpected function";
    assert hopAfter != hopBefore => f.selector == sig:file(bytes32,uint256).selector, "hop changed in an unexpected function";
    assert zzzAfter != zzzBefore => f.selector == sig:kick(uint256,uint256).selector, "zzz changed in an unexpected function";
    assert wantAfter != wantBefore => f.selector == sig:file(bytes32,uint256).selector, "want changed in an unexpected function";
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

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
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

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    uint256 hopBefore = hop();
    uint256 wantBefore = want();

    file(e, what, data);

    uint256 hopAfter = hop();
    uint256 wantAfter = want();

    assert what == to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000) => hopAfter == data, "file did not set hop";
    assert what != to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000) => hopAfter == hopBefore, "file did keep unchanged hop";
    assert what == to_bytes32(0x77616e7400000000000000000000000000000000000000000000000000000000) => wantAfter == data, "file did not set want";
    assert what != to_bytes32(0x77616e7400000000000000000000000000000000000000000000000000000000) => wantAfter == wantBefore, "file did keep unchanged want";
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000) && what != to_bytes32(0x77616e7400000000000000000000000000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file_address(bytes32 what, address data) {
    env e;

    file(e, what, data);

    address pipAfter = pip();

    assert pipAfter == data, "file did not set pip";
}

// Verify revert rules on file
rule file_address_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x7069700000000000000000000000000000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

definition getTotalDai(mathint wlot, mathint reserveDai) returns mathint = wlot * (997 * wlot + 1997 * reserveDai) / (1000 * reserveDai);
definition getAmountOut(mathint amtIn, mathint reserveIn, mathint reserveOut) returns mathint = amtIn * 997 * reserveOut / (reserveIn * 1000 + amtIn * 997);
definition isAprox(mathint value1, mathint value2, mathint tolerance) returns bool = value1 >= value2 ? value1 - value2 <= tolerance : value2 - value1 <= tolerance;

// Verify correct storage changes for non reverting kick
rule kick(uint256 lot, uint256 a) {
    env e;

    require e.msg.sender != daiJoin;
    require daiFirst();

    require lot > 0;

    mathint want = want();
    require want == 980000000000000000;
    address receiver = receiver();

    mathint vatDaiSenderBefore = vat.dai(e.msg.sender);
    mathint pairReservesDaiBefore; mathint pairReservesMkrBefore; mathint b;
    pairReservesDaiBefore, pairReservesMkrBefore, b = pair.getReserves();
    require pairReservesDaiBefore > 0;
    require pairReservesMkrBefore > 0;
    mathint daiBalanceOfPairBefore = dai.balanceOf(pair);
    mathint mkrBalanceOfPairBefore = mkr.balanceOf(pair);
    require daiBalanceOfPairBefore == pairReservesDaiBefore;
    require mkrBalanceOfPairBefore == pairReservesMkrBefore;
    // require daiBalanceOfPairBefore >= pairReservesDaiBefore;
    // require mkrBalanceOfPairBefore >= pairReservesMkrBefore;
    // require daiBalanceOfPairBefore / mkrBalanceOfPairBefore >= 100;
    // require daiBalanceOfPairBefore / mkrBalanceOfPairBefore <= 10000;
    mathint pairBalanceOfReceiverBefore = pair.balanceOf(receiver);
    mathint pairTotalSupplyBefore = pair.totalSupply();
    // require pairTotalSupplyBefore == to_mathint(aux.sqrt(require_uint256(pairReservesDaiBefore * pairReservesMkrBefore)));
    require pairTotalSupplyBefore > to_mathint(pair.MINIMUM_LIQUIDITY());
    require pairTotalSupplyBefore * pairTotalSupplyBefore == pairReservesDaiBefore * pairReservesMkrBefore;
    require pairTotalSupplyBefore >= pairBalanceOfReceiverBefore;

    mathint wlot = lot / RAY();
    mathint totalDai = getTotalDai(wlot, daiBalanceOfPairBefore);
    mathint bought = getAmountOut(wlot, daiBalanceOfPairBefore, mkrBalanceOfPairBefore);

    kick(e, lot, a);

    mathint vatDaiSenderAfter = vat.dai(e.msg.sender);
    mathint pairReservesDaiAfter; mathint pairReservesMkrAfter;
    pairReservesDaiAfter, pairReservesMkrAfter, b = pair.getReserves();
    mathint daiBalanceOfPairAfter = dai.balanceOf(pair);
    mathint mkrBalanceOfPairAfter = mkr.balanceOf(pair);
    mathint pairBalanceOfReceiverAfter = pair.balanceOf(receiver);
    mathint pairTotalSupplyAfter = pair.totalSupply();

    assert vatDaiSenderAfter == vatDaiSenderBefore - totalDai * RAY(), "kick did not decrease vat.dai(sender) by totalDai * RAY()";
    assert pairReservesDaiAfter == daiBalanceOfPairBefore + totalDai, "kick did not increase the reserves by totalDai + existing difference with the balance";
    assert pairReservesMkrAfter == mkrBalanceOfPairBefore, "kick did not keep the reserves as the balance";
    assert pairReservesDaiAfter == daiBalanceOfPairAfter, "kick did not leave dai reserves synced";
    assert pairReservesMkrAfter == mkrBalanceOfPairAfter, "kick did not leave mkr reserves synced";
    assert pairBalanceOfReceiverAfter > pairBalanceOfReceiverBefore, "kick did not increase the pair balance of receiver";
    mathint liquidityGained = pairBalanceOfReceiverAfter - pairBalanceOfReceiverBefore;
    require bought > liquidityGained * pairReservesMkrAfter / pairTotalSupplyAfter;
    assert bought - liquidityGained * pairReservesMkrAfter / pairTotalSupplyAfter <= 1000;
    // assert isAprox(bought, liquidityGained * pairReservesMkrAfter / pairTotalSupplyAfter, 1000), "kick did not leave the amount of mkr that can be withdrawn aprox the same than the bought one";
    // assert isAprox(totalDai - wlot, liquidityGained * pairReservesDaiAfter / pairTotalSupplyAfter, 1000), "kick did not leave the amount of dai that can be withdrawn aprox the same than the deposited one";
}

// Verify revert rules on kick
rule kick_revert(uint256 lot, uint256 a) {
    env e;

    require pair.unlocked() == 1;

    mathint wardsSender = wards(e.msg.sender);
    mathint live = live();
    mathint zzz = zzz();
    mathint hop = hop();
    mathint want = want();
    address receiver = receiver();

    mathint vatDaiSender = vat.dai(e.msg.sender);
    mathint vatDaiFlapper = vat.dai(currentContract);
    mathint vatDaiDaiJoin = vat.dai(daiJoin);
    mathint vatCanSenderFlapper = vat.can(e.msg.sender, currentContract);
    mathint vatCanFlapperDaiJoin = vat.can(currentContract, daiJoin);
    mathint pairReservesDai; mathint pairReservesMkr; mathint b;
    pairReservesDai, pairReservesMkr, b = pair.getReserves();
    mathint daiBalanceOfPair = dai.balanceOf(pair);
    mathint mkrBalanceOfPair = mkr.balanceOf(pair);
    mathint mkrBalanceOfFlapper = mkr.balanceOf(currentContract);
    mathint pairBalanceOfReceiver = pair.balanceOf(receiver);
    mathint pairTotalSupply = pair.totalSupply();

    require pairTotalSupply >= pairBalanceOfReceiver;
    require pairReservesDai > 0;
    require pairReservesMkr > 0;
    require daiBalanceOfPair >= pairReservesDai;
    require mkrBalanceOfPair >= pairReservesMkr;

    mathint wlot = lot / RAY();
    mathint totalDai = getTotalDai(wlot, daiBalanceOfPair);
    mathint bought = getAmountOut(wlot, daiBalanceOfPair, mkrBalanceOfPair);

    mathint price = pip.read();
    mathint par = spotter.par();
    require par > 0;
    require (price * RAY() / par) > 0;

    kick@withrevert(e, lot, a);

    bool revert1  = e.msg.value > 0;
    bool revert2  = wardsSender != 1;
    bool revert3  = live != 1;
    bool revert4  = zzz + hop > max_uint256;
    bool revert5  = to_mathint(e.block.timestamp) < zzz + hop;
    bool revert6  = daiBalanceOfPair > maxuint112() || mkrBalanceOfPair > maxuint112();
    bool revert7  = wlot * (997 * wlot + 1997 * daiBalanceOfPair) > max_uint256;
    bool revert8  = totalDai >= lot * 220 / 100;
    bool revert9  = wlot * 997 * mkrBalanceOfPair > max_uint256;
    bool revert10 = daiBalanceOfPair * 100 + (wlot * 997) > max_uint256;
    bool revert11 = wlot * want > max_uint256;
    bool revert12 = price * RAY() > max_uint256;
    bool revert13 = bought < wlot * want / (price * RAY() / par);
    bool revert14 = vatCanSenderFlapper != 1;
    bool revert15 = vatDaiSender < totalDai * RAY();
    bool revert16 = vatDaiFlapper + totalDai * RAY() > max_uint256;
    bool revert17 = vatCanFlapperDaiJoin != 1;
    bool revert18 = vatDaiDaiJoin + totalDai * RAY() > max_uint256;
    bool revert19 = bought == 0;
    bool revert20 = bought > mkrBalanceOfPair;
    bool revert21 = mkrBalanceOfFlapper + bought > max_uint256;
    bool revert22 = daiBalanceOfPair + totalDai > max_uint256;
    bool revert23 = mkrBalanceOfPair + bought > max_uint256;

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15 ||
                            revert16 || revert17 || revert18 ||
                            revert19 || revert20 || revert21 ||
                            revert22 || revert23, "Revert rules failed";
}

// Verify correct storage changes for non reverting cage
rule cage() {
    env e;

    uint256 random;
    cage(e, random);

    mathint liveAfter = live();

    assert liveAfter == 0, "cage did not set live to 0";
}

// Verify revert rules on cage
rule cage_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    uint256 random;
    cage@withrevert(e, random);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
