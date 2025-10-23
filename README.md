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

### OracleWrapper

Allows for scaling down an oracle price by a certain value. This can be useful when the `gem` is a redenominated version of an existing token, which already has a reliable oracle.

### General Note:

* Availability and accounting of the withdrawn `USDS` is the responsibility of the `vow`. At the time of a `kick`, the `vow` is expected to hold at least the drawn amount (`vow.bump`) over the configured flapping threshold (`vow.hump`).
