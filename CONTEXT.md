# lenovo-power

Controls the power settings of a Lenovo Legion laptop on Linux.

The vocabulary below covers the two halves of that: raising a power budget, and
the thermal guard that gives it back.

## Language

### Raising a budget

**power budget**:
The watts the hardware is permitted to draw. The platform profile, the CPU
limits and the dGPU cap each set one.
_Avoid_: power limit, power cap (each names one specific setting, not the
concept), headroom

**raise**:
A change that increases a power budget. Every raise passes the gate and is
recorded in the armed set.
_Avoid_: boost, unlock, overclock (a raise changes watts at stock clocks; no
multiplier and no voltage is touched)

**raising profile**:
A platform profile whose selection is itself a raise: `max-power` and `custom`.
_Avoid_: the armed set (that is the record a raise leaves, not the list of
profiles that count as one)

**the gate**:
The confirmation a raise must pass before it is applied. It refuses outright
while the CPU is already at the guard's trigger temperature.
_Avoid_: guardrail, prompt (the prompt is what the gate shows, not the gate)

### Giving it back

**the armed set**:
The record of every raise that has not yet been given back. Each entry holds the
setting's value from before the raise.
_Avoid_: ledger, restore list, pending set

**give back**:
The guard's reversal of a raise. Deliberately not a return to the recorded prior
value: the platform profile goes to `performance`, and the dGPU cap goes to the
card's default.
_Avoid_: restore, revert, roll back (each promises the prior value)

**the guard**:
The policy that gives back raises when the CPU stays hot. It is a comfort and
longevity policy, separate from the firmware's thermal ladder, which it neither
replaces nor weakens.
_Avoid_: thermal protection, damage protection, throttling

**the latch**:
The hold that follows a give-back. It keeps the machine at the lowered budget
until the user deliberately raises again.
_Avoid_: cooldown, lockout
