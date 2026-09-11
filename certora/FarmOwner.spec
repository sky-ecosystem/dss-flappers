// FarmOwner.spec

using FarmMock as farm;
using Usds as usds;

methods {
    function wards(address) external returns (uint256) envfree;
    function farm.owner() external returns (address) envfree;
    function farm.nominatedOwner() external returns (address) envfree;
    function farm.rewardsDuration() external returns (uint256) envfree;
    function farm.rewardsDistribution() external returns (address) envfree;
    function farm.paused() external returns (bool) envfree;
    function usds.balanceOf(address) external returns (uint256) envfree;
    function usds.totalSupply() external returns (uint256) envfree;
    function _.transfer(address, uint256) external => DISPATCHER(true);
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
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

// Verify correct farm changes for non reverting setRewardsDuration
rule setRewardsDuration(uint256 duration) {
    env e;

    setRewardsDuration(e, duration);

    assert farm.rewardsDuration() == duration;
}

// Verify revert rules on setRewardsDuration
rule setRewardsDuration_revert(uint256 duration) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    require farm.owner() == currentContract;

    setRewardsDuration@withrevert(e, duration);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct farm changes for non reverting setRewardsDistribution
rule setRewardsDistribution(address rewardsDistribution) {
    env e;

    setRewardsDistribution(e, rewardsDistribution);

    assert farm.rewardsDistribution() == rewardsDistribution;
}

// Verify revert rules on setRewardsDistribution
rule setRewardsDistribution_revert(address rewardsDistribution) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    require farm.owner() == currentContract;

    setRewardsDistribution@withrevert(e, rewardsDistribution);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct farm changes for non reverting setPaused
rule setPaused(bool paused) {
    env e;

    setPaused(e, paused);

    assert farm.paused() == paused;
}

// Verify revert rules on setPaused
rule setPaused_revert(bool paused) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    require farm.owner() == currentContract;

    setPaused@withrevert(e, paused);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct farm changes for non reverting nominateNewOwner
rule nominateNewOwner(address usr) {
    env e;

    nominateNewOwner(e, usr);

    assert farm.nominatedOwner() == usr;
}

// Verify revert rules on nominateNewOwner
rule nominateNewOwner_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    require farm.owner() == currentContract;

    nominateNewOwner@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// Verify correct farm changes for non reverting acceptOwnership
rule acceptOwnership() {
    env e;

    acceptOwnership(e);

    assert farm.owner() == currentContract;
    assert farm.nominatedOwner() == 0;
}

// Verify revert rules on acceptOwnership
rule acceptOwnership_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    address farmNominatedOwner = farm.nominatedOwner();

    acceptOwnership@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    // the farm hands over ownership to its nominee, not to its current owner
    bool revert3 = farmNominatedOwner != currentContract;

    assert lastReverted <=> revert1 || revert2 || revert3;
}

// Verify correct balance changes for non reverting recoverERC20
rule recoverERC20(address tokenAddress, address to, uint256 amount) {
    env e;

    require to != farm;
    require to != currentContract;
    require tokenAddress == usds;

    mathint usdsBalanceOfFarmBefore = usds.balanceOf(farm);
    mathint usdsBalanceOfFarmOwnerBefore = usds.balanceOf(currentContract);
    mathint usdsBalanceOfToBefore = usds.balanceOf(to);

    require usds.totalSupply() >= usdsBalanceOfFarmBefore + usdsBalanceOfFarmOwnerBefore + usdsBalanceOfToBefore;

    recoverERC20(e, tokenAddress, to, amount);

    mathint usdsBalanceOfFarmAfter = usds.balanceOf(farm);
    mathint usdsBalanceOfFarmOwnerAfter = usds.balanceOf(currentContract);
    mathint usdsBalanceOfToAfter = usds.balanceOf(to);

    // The recovered tokens are passed through, none of them are stranded in the FarmOwner
    assert usdsBalanceOfFarmAfter == usdsBalanceOfFarmBefore - amount;
    assert usdsBalanceOfFarmOwnerAfter == usdsBalanceOfFarmOwnerBefore;
    assert usdsBalanceOfToAfter == usdsBalanceOfToBefore + amount;
}

// Verify revert rules on recoverERC20
rule recoverERC20_revert(address tokenAddress, address to, uint256 amount) {
    env e;

    require to != farm;
    require to != currentContract;
    require to != 0 && to != usds;
    require tokenAddress == usds;

    mathint wardsSender = wards(e.msg.sender);
    require farm.owner() == currentContract;
    require usds.balanceOf(farm) >= amount;

    // Token invariant, so the transfers can not overflow a balance
    require usds.totalSupply() >= usds.balanceOf(farm) + usds.balanceOf(currentContract) + usds.balanceOf(to);

    recoverERC20@withrevert(e, tokenAddress, to, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}
