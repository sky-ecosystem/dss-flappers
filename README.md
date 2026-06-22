# Dss Flappers

Implementations of MakerDAO surplus auctions, triggered on `vow.flap` or via new `kicker.flap`.

### Kicker

Implements a Splitter/Flapper calling function that replaces `Vow.flap` and can be called even when `Vat.dai(Vow) < Vat.sin(Vow)`.
The triggering threshold is assumed to be carefully set up and controlled by governance, ensuring there is enough surplus secured (in the Vow based surplus buffer or elsewhere).

Configurable Parameters:
* `kbump` - Fixed lot size (`RAD` precision)
* `khump` - Flap threshold (`RAD` precision, signed integer value).

Note: It is assumed that the `Flop` auctions mechanism is disabled and remains in that state. As otherwise it could collide with the above mechanism.
Currently this is done through the configuration of `Vow.sump` as max uint256 (aka infinity).

Note 2: Rate limiting is ensured via the `Splitter`.

Note 3: Stop functionality is implemented via the `Splitter.cage` function (reason to leave the `Splitter` as `flapper` reference in the `Vow` and the `wards` still set). However, even if `Vow.cage` remains functional, in order to execute `End.cage` it is still necessary a deep analysis and prior actions in different modules to be executed successfully.

### Splitter

Exposes a `kick` operation to be triggered periodically. Its logic withdraws `USDS` from the `vow` and splits it in two parts. The first part (`burn`) is sent to the underlying `flapper` contract to be processed by the burn engine. The second part (`WAD - burn`) is distributed as reward to a `farm` contract. The `kick` cadence is determined by the `hop` value.

Configurable Parameters:
* `burn` - The percentage of the `vow.bump` to be moved to the underlying `flapper`. For example, a value of 0.70 \* `WAD` corresponds to funneling 70% of the `USDS` to the burn engine.
* `hop` - Minimum seconds interval between kicks.
* `flapper` - The underlying burner strategy (e.g. the address of `FlapperUniV2SwapOnly`).
* `farm` - The staking rewards contract receiving the rewards.

### FlapperUniV2

Exposes an `exec` operation to be triggered periodically by the `Splitter` (at a cadence determined by `Splitter.hop()`). Its logic withdraws `USDS` from the `Splitter` and buys `gem` tokens on Uniswap v2. The acquired tokens, along with a proportional amount of `USDS` (saved from the initial withdraw) are deposited back into the liquidity pool. Finally, the minted LP tokens are sent to a predefined `receiver` address.

Configurable Parameters:
* `pip` - A reference price oracle, used for bounding the exchange rate of the swap.
* `want` - Relative multiplier of the reference price to insist on in the swap. For example, a value of 0.98 * `WAD` allows for a 2% worse price than the reference.

#### Note:

* Although the Flapper interface is conformant with the Emergency Shutdown procedure and will stop operating when it is triggered, LP tokens already sent to the `receiver` do not have special redeeming handling. Therefore, in case the Pause Proxy is the `receiver` and governance does not control it, the LP tokens can be lost or seized by a governance attack.

### FlapperUniV2SwapOnly

Exposes an `exec` operation to be triggered periodically by the `Splitter` (at a cadence determined by `Splitter.hop()`). Its logic withdraws `USDS` from the `Splitter` and buys `gem` tokens on Uniswap v2. The acquired tokens are sent to a predefined `receiver` address.

Configurable Parameters:
* `pip` - A reference price oracle, used for bounding the exchange rate of the swap.
* `want` - Relative multiplier of the reference price to insist on in the swap. For example, a value of 0.98 * `WAD` allows for a 2% worse price than the reference.

### SplitterMom

This contract allows bypassing the governance delay when disabling the Splitter in an emergency.

### FarmOwner

Holds ownership of an external Synthetix-style `StakingRewards` farm (the `Splitter.farm`) on behalf of governance. The farm exposes a single-owner administration model, so `FarmOwner` takes that owner slot and re-exposes every `onlyOwner` method as a ward-gated forwarder. This lets multiple wards (typically the `MCD_PAUSE_PROXY` and the `SBEBeam`) share farm administration while the farm itself only ever knows one owner.

### SBEBeam

A bounded, rate-limited parameter setter for the Smart Burn Engine. It allows a permissioned `facilitator` (a `bud`) to periodically adjust the three core burn-engine knobs within governance-defined safety bounds, without going through the full governance delay each time. In a single `set` call it atomically updates:
* `Kicker.kbump` - Fixed lot size.
* `Splitter.burn` - Percentage of surplus routed to the burn engine.
* `Splitter.hop` - Kick cadence (also applied to the farm's `rewardsDuration` via `FarmOwner`).

The bounds only constrain the throughput-increasing directions, so a facilitator can never accelerate the burn beyond what governance has sanctioned. The opposite moves — lowering `kbump` or raising `hop` — are always permitted: at worst they stall the burn stream (a denial of service), which governance can revive on its own. This asymmetry is what makes the module safe to drive with an operator. `burn` is additionally capped at `WAD` (100%), since the `Splitter` does not validate it and a value above `WAD` would make `Splitter.kick` underflow and halt.

Configurable Parameters:
* `maxKbump` - Maximum allowed value for `Kicker.kbump`. There is no minimum; `kbump` may be lowered freely, but it must be a whole multiple of `RAY` (matching the `Kicker` deploy invariant and avoiding `kick` rounding dust).
* `minHop` - Minimum allowed value for `Splitter.hop`. There is no maximum; `hop` may be raised freely, except it cannot be set to `type(uint256).max` — that value is the halt sentinel reserved for governance (see Halting below), so a facilitator cannot use `set` to halt the engine and lock itself out.
* `maxRate` - Maximum allowed burn rate, measured as `kbump / hop` (the total surplus throughput). This caps the combined throughput even when `kbump` and `hop` are each individually within their own bound.
* `tau` - Cooldown period (in seconds) enforced between consecutive `set` calls.
* `toc` - Timestamp of the last `set` call.

`Splitter.burn` is bounded only at its upper end (`burn <= WAD`); it may be lowered freely down to zero.

Access control:
* `wards` (`rely`/`deny`) - Governance-level administrators that configure the ranges.
* `buds` (`kiss`/`diss`) - Facilitators permitted to call `set`.

Halting: `set` is automatically blocked whenever the burn engine itself is stopped, i.e. when `Splitter.hop` is set to `type(uint256).max` (the canonical way governance disables kicks, since `Splitter.kick` then becomes unreachable). This binds the `SBEBeam` halt state to the engine's real halt state — there is no separate flag to keep in sync — and it ensures a facilitator can never use `set` to revive a governance-halted engine. Only governance can bring it back, by re-filing a finite `hop` on the `Splitter`.

Note: `SBEBeam` must be a ward of `Kicker`, `Splitter`, and `FarmOwner` for its `set` call to succeed.

### OracleWrapper

Allows for scaling down an oracle price by a certain value. This can be useful when the `gem` is a redenominated version of an existing token, which already has a reliable oracle.

### General Note:

* Availability and accounting of the withdrawn `USDS` is the responsibility of the `vow`. At the time of a `kick`, the `vow` is expected to hold at least the drawn amount (`vow.bump`) over the configured flapping threshold (`vow.hump`).
