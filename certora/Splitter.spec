// Splitter.spec

using Vat as vat;
using UsdsJoin as usdsJoin;
using Usds as usds;
using Sky as sky;
using SpotterMock as spotter;
using PipMock as pip;
using UniswapV2Pair as pair;
using FlapperUniV2SwapOnly as flapper;
using FarmMock as farm;

methods {
    function wards(address) external returns (uint256) envfree;
    function live() external returns (uint256) envfree;
    function flapper() external returns (address) envfree;
    function farm() external returns (address) envfree;
    function burn() external returns (uint256) envfree;
    function hop() external returns (uint256) envfree;
    function zzz() external returns (uint256) envfree;
    function vat.can(address, address) external returns (uint256) envfree;
    function vat.dai(address) external returns (uint256) envfree;
    function usds.wards(address) external returns (uint256) envfree;
    function usds.balanceOf(address) external returns (uint256) envfree;
    function usds.totalSupply() external returns (uint256) envfree;
    function sky.balanceOf(address) external returns (uint256) envfree;
    function sky.totalSupply() external returns (uint256) envfree;
    function pip.read() external returns (uint256) envfree;
    function spotter.par() external returns (uint256) envfree;
    function pair.getReserves() external returns (uint112, uint112, uint32) envfree;
    function pair.unlocked() external returns (uint256) envfree;
    function flapper.wards(address) external returns (uint256) envfree;
    function flapper.want() external returns (uint256) envfree;
    function flapper.receiver() external returns (address) envfree;
    function flapper.usdsFirst() external returns (bool) envfree;
    function farm.lastReward() external returns (uint256) envfree;
    function farm.notifications() external returns (uint256) envfree;
    function _.uniswapV2Call(address, uint256, uint256, bytes) external => NONDET;
}

definition RAY() returns mathint = 10^27;
definition RAD() returns mathint = 10^45;
definition maxuint112() returns mathint = 2^112 - 1;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint liveBefore = live();
    address flapperBefore = flapper();
    address farmBefore = farm();
    mathint burnBefore = burn();
    mathint hopBefore = hop();
    mathint zzzBefore = zzz();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint liveAfter = live();
    address flapperAfter = flapper();
    address farmAfter = farm();
    mathint burnAfter = burn();
    mathint hopAfter = hop();
    mathint zzzAfter = zzz();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
    assert liveAfter != liveBefore => f.selector == sig:cage(uint256).selector;
    assert flapperAfter != flapperBefore => f.selector == sig:file(bytes32,address).selector;
    assert farmAfter != farmBefore => f.selector == sig:file(bytes32,address).selector;
    assert burnAfter != burnBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert hopAfter != hopBefore => f.selector == sig:file(bytes32,uint256).selector;
    assert zzzAfter != zzzBefore => f.selector == sig:kick(uint256,uint256).selector;
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

    mathint burnBefore = burn();
    mathint hopBefore = hop();

    file(e, what, data);

    mathint burnAfter = burn();
    mathint hopAfter = hop();

    assert what == to_bytes32(0x6275726e00000000000000000000000000000000000000000000000000000000) => burnAfter == data; // "burn"
    assert what != to_bytes32(0x6275726e00000000000000000000000000000000000000000000000000000000) => burnAfter == burnBefore;
    assert what == to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000) => hopAfter == data; // "hop"
    assert what != to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000) => hopAfter == hopBefore;
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6275726e00000000000000000000000000000000000000000000000000000000) && // "burn"
                   what != to_bytes32(0x686f700000000000000000000000000000000000000000000000000000000000);   // "hop"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

// Verify correct storage changes for non reverting file
rule file_address(bytes32 what, address data) {
    env e;

    address flapperBefore = flapper();
    address farmBefore = farm();

    file(e, what, data);

    address flapperAfter = flapper();
    address farmAfter = farm();

    assert what == to_bytes32(0x666c617070657200000000000000000000000000000000000000000000000000) => flapperAfter == data; // "flapper"
    assert what != to_bytes32(0x666c617070657200000000000000000000000000000000000000000000000000) => flapperAfter == flapperBefore;
    assert what == to_bytes32(0x6661726d00000000000000000000000000000000000000000000000000000000) => farmAfter == data; // "farm"
    assert what != to_bytes32(0x6661726d00000000000000000000000000000000000000000000000000000000) => farmAfter == farmBefore;
}

// Verify revert rules on file
rule file_address_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x666c617070657200000000000000000000000000000000000000000000000000) && // "flapper"
                   what != to_bytes32(0x6661726d00000000000000000000000000000000000000000000000000000000);   // "farm"

    assert lastReverted <=> revert1 || revert2 || revert3;
}

definition getAmountOut(mathint amtIn, mathint reserveIn, mathint reserveOut) returns mathint =
    amtIn * 997 * reserveOut / (reserveIn * 1000 + amtIn * 997);

// Verify correct storage and balance changes for non reverting kick
rule kick(uint256 tot, uint256 a) {
    env e;

    // The Splitter is both the source and the destination of the internal moves
    require e.msg.sender != currentContract;
    require e.msg.sender != usdsJoin;

    require flapper.usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)
    require pair.unlocked() == 1;

    address receiver = flapper.receiver();
    require receiver != pair;

    // Set up by the constructor and the init spell
    require vat.can(currentContract, usdsJoin) == 1;
    require usds.wards(usdsJoin) == 1;
    require flapper.wards(currentContract) == 1;

    mathint burn = burn();

    // Note - the swap only flapper prices with the stored reserves
    mathint reserveUsds; mathint reserveGem; mathint b;
    reserveUsds, reserveGem, b = pair.getReserves();
    require reserveUsds > 0 && reserveGem > 0;

    require farm.notifications() == 0;

    mathint vatDaiSenderBefore = vat.dai(e.msg.sender);
    mathint vatDaiSplitterBefore = vat.dai(currentContract);
    mathint vatDaiUsdsJoinBefore = vat.dai(usdsJoin);
    mathint usdsTotalSupplyBefore = usds.totalSupply();
    mathint usdsBalanceOfFlapperBefore = usds.balanceOf(flapper);
    mathint usdsBalanceOfPairBefore = usds.balanceOf(pair);
    mathint usdsBalanceOfFarmBefore = usds.balanceOf(farm);
    mathint skyBalanceOfPairBefore = sky.balanceOf(pair);
    mathint skyBalanceOfReceiverBefore = sky.balanceOf(receiver);

    require usdsTotalSupplyBefore >= usdsBalanceOfFlapperBefore + usdsBalanceOfPairBefore + usdsBalanceOfFarmBefore;
    require sky.totalSupply() >= skyBalanceOfPairBefore + skyBalanceOfReceiverBefore;

    mathint lot = tot * burn / RAD();
    mathint pay = tot / RAY() - lot;
    mathint buy = getAmountOut(lot, reserveUsds, reserveGem);

    mathint id = kick(e, tot, a);

    mathint vatDaiSenderAfter = vat.dai(e.msg.sender);
    mathint vatDaiSplitterAfter = vat.dai(currentContract);
    mathint vatDaiUsdsJoinAfter = vat.dai(usdsJoin);
    mathint usdsTotalSupplyAfter = usds.totalSupply();
    mathint usdsBalanceOfFlapperAfter = usds.balanceOf(flapper);
    mathint usdsBalanceOfPairAfter = usds.balanceOf(pair);
    mathint usdsBalanceOfFarmAfter = usds.balanceOf(farm);
    mathint skyBalanceOfPairAfter = sky.balanceOf(pair);
    mathint skyBalanceOfReceiverAfter = sky.balanceOf(receiver);
    mathint farmNotificationsAfter = farm.notifications();

    assert id == 0;
    assert zzz() == e.block.timestamp;
    assert vatDaiSenderAfter == vatDaiSenderBefore - tot;
    assert vatDaiSplitterAfter == vatDaiSplitterBefore + tot - (lot + pay) * RAY();
    assert vatDaiUsdsJoinAfter == vatDaiUsdsJoinBefore + (lot + pay) * RAY();
    assert usdsTotalSupplyAfter == usdsTotalSupplyBefore + lot + pay;
    assert usdsBalanceOfFarmAfter == usdsBalanceOfFarmBefore + pay;
    // The whole exited amount is swapped, so the flapper is left with no usds
    assert usdsBalanceOfFlapperAfter == usdsBalanceOfFlapperBefore;
    assert usdsBalanceOfPairAfter == usdsBalanceOfPairBefore + lot;
    assert lot > 0 => skyBalanceOfPairAfter == skyBalanceOfPairBefore - buy;
    assert lot > 0 => skyBalanceOfReceiverAfter == skyBalanceOfReceiverBefore + buy;
    assert lot == 0 => skyBalanceOfPairAfter == skyBalanceOfPairBefore;
    assert lot == 0 => skyBalanceOfReceiverAfter == skyBalanceOfReceiverBefore;
    assert pay > 0 => farm.lastReward() == pay;
    assert pay > 0 => farmNotificationsAfter == 1;
    assert pay == 0 => farmNotificationsAfter == 0;
}

// Verify revert rules on kick
rule kick_revert(uint256 tot, uint256 a) {
    env e;

    // The Splitter is both the source and the destination of the internal moves
    require e.msg.sender != currentContract;
    require e.msg.sender != usdsJoin;

    require flapper.usdsFirst(); // The `!usdsFirst` case is symmetric (usds is linked as token0 of the pair)
    require pair.unlocked() == 1;

    address receiver = flapper.receiver();

    mathint wardsSender = wards(e.msg.sender);
    mathint live = live();
    mathint zzz = zzz();
    mathint hop = hop();
    mathint burn = burn();
    mathint want = flapper.want();

    mathint vatCanSplitterUsdsJoin = vat.can(currentContract, usdsJoin);
    mathint usdsWardsUsdsJoin = usds.wards(usdsJoin);
    mathint flapperWardsSplitter = flapper.wards(currentContract);
    mathint vatCanSenderSplitter = vat.can(e.msg.sender, currentContract);

    mathint reserveUsds; mathint reserveGem; mathint b;
    reserveUsds, reserveGem, b = pair.getReserves();
    require reserveUsds > 0 && reserveGem > 0;

    mathint vatDaiSender = vat.dai(e.msg.sender);
    mathint vatDaiSplitter = vat.dai(currentContract);
    mathint vatDaiUsdsJoin = vat.dai(usdsJoin);
    mathint usdsTotalSupply = usds.totalSupply();
    mathint usdsBalanceOfPair = usds.balanceOf(pair);
    mathint skyBalanceOfPair = sky.balanceOf(pair);
    mathint skyBalanceOfReceiver = sky.balanceOf(receiver);
    require usdsBalanceOfPair >= reserveUsds;
    require skyBalanceOfPair >= reserveGem;
    // Token invariants, so the mints and the transfers can not overflow a balance
    require usds.balanceOf(flapper) + usds.balanceOf(farm) + usdsBalanceOfPair <= usdsTotalSupply;
    require receiver != pair => skyBalanceOfPair + skyBalanceOfReceiver <= sky.totalSupply();

    mathint lot = tot * burn / RAD();
    mathint pay = tot / RAY() - lot;
    mathint buy = getAmountOut(lot, reserveUsds, reserveGem);

    mathint price = pip.read();
    mathint par = spotter.par();
    require par > 0;

    kick@withrevert(e, tot, a);

    // auth and hop
    bool revert1  = e.msg.value > 0;
    bool revert2  = wardsSender != 1;
    bool revert3  = live != 1;
    bool revert4  = zzz + hop > max_uint256;
    bool revert5  = e.block.timestamp < zzz + hop;
    // vat.move(sender, splitter, tot) - the vat sees the Splitter as the caller
    bool revert6  = vatCanSenderSplitter != 1;
    bool revert7  = vatDaiSender < tot;
    bool revert8  = vatDaiSplitter + tot > max_uint256;
    // lot and pay
    bool revert9  = tot * burn > max_uint256;
    bool revert10 = lot > tot / RAY();
    // usdsJoin.exit(flapper, lot) and usdsJoin.exit(farm, pay)
    bool revert11 = lot + pay > 0 && vatCanSplitterUsdsJoin != 1;
    bool revert12 = lot + pay > 0 && usdsWardsUsdsJoin != 1;
    bool revert13 = lot > 0 && lot * RAY() > max_uint256;
    bool revert14 = pay > 0 && pay * RAY() > max_uint256;
    bool revert15 = lot > 0 && vatDaiSplitter + tot < lot * RAY();
    bool revert16 = pay > 0 && vatDaiSplitter + tot - lot * RAY() < pay * RAY();
    bool revert17 = lot + pay > 0 && vatDaiUsdsJoin + (lot + pay) * RAY() > max_uint256;
    bool revert18 = usdsTotalSupply + lot + pay > max_uint256;
    // flapper.exec(lot)
    bool revert19 = lot > 0 && flapperWardsSplitter != 1;
    bool revert20 = lot > 0 && lot * 997 > max_uint256;
    bool revert21 = lot > 0 && lot * 997 * reserveGem > max_uint256;
    bool revert22 = lot > 0 && reserveUsds * 1000 + lot * 997 > max_uint256;
    bool revert23 = lot > 0 && price * RAY() > max_uint256;
    bool revert24 = lot > 0 && price * RAY() / par == 0;
    bool revert25 = lot > 0 && lot * want > max_uint256;
    bool revert26 = lot > 0 && !revert24 && buy < lot * want / (price * RAY() / par);
    bool revert27 = lot > 0 && buy == 0;
    bool revert28 = lot > 0 && buy >= reserveGem;
    // the pair rejects the tokens as `to`, sky itself rejects the zero address
    bool revert29 = lot > 0 && (receiver == usds || receiver == sky || receiver == 0);
    bool revert30 = lot > 0 && (usdsBalanceOfPair + lot > maxuint112() ||
                                skyBalanceOfPair - (receiver != pair ? buy : 0) > maxuint112());

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15 ||
                            revert16 || revert17 || revert18 ||
                            revert19 || revert20 || revert21 ||
                            revert22 || revert23 || revert24 ||
                            revert25 || revert26 || revert27 ||
                            revert28 || revert29 || revert30;
}

// Verify correct storage changes for non reverting cage
rule cage() {
    env e;

    uint256 random;
    cage(e, random);

    mathint liveAfter = live();

    assert liveAfter == 0;
}

// Verify revert rules on cage
rule cage_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    uint256 random;
    cage@withrevert(e, random);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}
