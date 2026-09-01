# lenovo-power

Power controls and a small status panel for Lenovo Legion laptops on Linux,
built on the upstream `lenovo_wmi_*` and `ideapad_laptop` kernel drivers.

Developed against a **Legion Pro 5 16IAX10H** (Core Ultra 9 275HX, RTX 5070 Ti
Mobile) on Arch with kernel 7.1. Other Legion models exposing the same sysfs
attributes should work; every read degrades to `-` when an attribute is absent.

## Why

`power-profiles-daemon` exposes three profiles. The firmware on these machines
exposes five, plus CPU power limits, battery conservation mode, EPP, turbo and
per-fan telemetry. This wraps all of it in one CLI and one panel.

## Profiles: the bar already switches three of them

On this desktop the bar's power widget (Omarchy's `omarchy.power` module, in
`~/.config/omarchy/shell.json`) is already a profile switcher. Click it and the
panel lists one button per `power-profiles-daemon` profile -- **power-saver**,
**balanced**, **performance** -- and clicking one applies it through
`omarchy-powerprofiles-set`, the same helper `lenovo-power profile` calls for
those same three (the CLI passes `autodetect`, the panel passes `ac` or
`battery` outright). For the switch you make most often, the bar is the shorter
route; the terminal buys you nothing.

What the bar cannot reach is the other two profiles this firmware exposes:
**max-power** and **custom**. `power-profiles-daemon` has no concept of them, so
they never appear in the panel. Those two are what this CLI adds on top --
`max-power` working normally, `custom` rejected by this firmware for a reason
that has nothing to do with the bar (see the caveat below) -- along with the CPU
power budget, EPP, turbo, battery conservation, USB always-on and Fn lock, none
of which ppd knows about either.

## Install

```bash
git clone git@github.com:rwildcard/lenovo-power.git
cd lenovo-power
./install.sh            # symlinks bin/* into ~/.local/bin
lenovo-power install-perms   # one-time, asks for your password
```

`install-perms` grants the `wheel` group write access to the relevant sysfs
attributes and installs a systemd unit that reapplies it on every boot. Without
it the tools still read everything and fall back to `sudo` for writes.

## CLI

```
lenovo-power                    # full status (default)
lenovo-power profile [NAME]     # low-power | balanced | performance | max-power | custom
lenovo-power preset [NAME]      # quiet | travel | work | game | max
lenovo-power epp [PREF]         # power | balance_power | balance_performance | performance
lenovo-power turbo [on|off]
lenovo-power cpu-limit [PL1 [PL2]]   # watts; needs the 'custom' profile - see caveat
lenovo-power gpu-limit [WATTS]       # NVIDIA dGPU cap; needs sudo
lenovo-power battery-cap [on|off]    # conservation mode, holds charge at ~60%
lenovo-power usb-charging [on|off]
lenovo-power fn-lock [on|off]
```

Omit the argument to read a setting instead of writing it.

## GUI

`lenovo-power-gui` is a read-only GTK4/libadwaita panel that refreshes every two
seconds: profile, EPP, turbo, PL1/PL2, CPU frequency and temperature, dGPU power
and utilisation, battery draw and conservation mode, fan RPM, plus static specs.

## Design notes

- **Never wakes a sleeping dGPU.** Querying `nvidia-smi` resumes a
  runtime-suspended card and costs ~10 W. Both tools check
  `power/runtime_status` first and skip the query while it is suspended.
- **Does not fight power-profiles-daemon.** For the three profiles ppd knows,
  `profile` delegates to `omarchy-powerprofiles-set` (or `powerprofilesctl`) so
  ppd's state stays correct. Only `max-power` and `custom` are written straight
  to sysfs, and the tool warns that ppd may override them on the next AC change.
- **Writes fail fast.** A non-interactive caller (keybind, script) gets an error
  rather than a hanging sudo prompt, and a value the kernel rejects is reported
  as such rather than blamed on permissions.

## These commands do not overclock

`cpu-limit`, `profile max-power` and `preset max` change the CPU's **power
budget** -- how many watts the package is allowed to draw, sustained (PL1) and
in burst (PL2) -- at stock, Intel-rated clocks. Overclocking is a different
thing: raising the clock multiplier or the voltage. This tool does neither,
anywhere.

That is checkable rather than a promise. Every hardware write either binary
makes, in full:

| Command | Writes |
|---|---|
| `profile` | `platform_profile` (via ppd for the three it owns) |
| `epp` | `cpu*/cpufreq/energy_performance_preference` |
| `turbo` | `intel_pstate/no_turbo` |
| `cpu-limit` | `ppt_pl1_spl/current_value`, `ppt_pl2_sppt/current_value` |
| `gpu-limit` | `nvidia-smi -pl`, the dGPU's power cap |
| `battery-cap`, `usb-charging`, `fn-lock` | the three `VPC2004:*` toggles |

Outside the hardware, the CLI writes one file of its own -- the last-used preset
name, under `$XDG_STATE_HOME/lenovo-power` -- and `install-perms` writes a
helper and a systemd unit. `lenovo-power-gui` writes nothing at all; it is
read-only. There is no MSR
access, no `scaling_max_freq`, no voltage offset in the tree -- and the firmware
publishes no overclocking attribute to write even if the tool wanted one:
`/sys/class/firmware-attributes/lenovo-wmi-other-0/attributes/` contains exactly
two entries, and both are power limits.

### The budget stays inside the firmware's own published range

Lenovo's firmware publishes a minimum, maximum and default for each limit, and
`cpu-limit` reads those back at runtime and refuses anything outside them before
it writes. On this machine (Legion Pro 5 16IAX10H, BIOS Q6CN79WW):

| Limit | Attribute | Min | Max | Default |
|---|---|---|---|---|
| PL1 sustained | `ppt_pl1_spl` | 50 W | 135 W | 70 W |
| PL2 burst | `ppt_pl2_sppt` | 60 W | 210 W | 125 W |

`lenovo-power status` prints the live range and default beside the current
value, so you are reading your own firmware's numbers rather than these. The
highest budget the tool can ask for is the one Lenovo shipped as the ceiling.

On this firmware `cpu-limit` cannot currently be applied at all, for an
unrelated reason -- see the caveat below. The published range is what the
attributes accept when it can.

The dGPU cap is bounded the same way, though by someone else: `gpu-limit` does
no checking of its own and hands the value to `nvidia-smi`, which reports a
5-140 W range on the card here (70 W default) and refuses anything outside it.

## The firmware's thermal ladder

Underneath all of this the firmware runs its own staged thermal response, and it
runs first. It is published as ACPI trip points on the `TCPU` thermal zone. Read
yours:

```bash
z=$(dirname "$(grep -lx TCPU /sys/class/thermal/thermal_zone*/type | head -1)")
for t in "$z"/trip_point_*_type; do
  printf '%s\t%s\n' "$(cat "${t%_type}_temp")" "$(cat "$t")"
done | sort -n
```

The snippet prints millidegrees, and it prints eight trip points, because the
top three share one temperature. That is six distinct stages:

| CPU temperature | Trip type | What the firmware does |
|---|---|---|
| 103.05 °C | active | first fan stage |
| 104.55 °C | active | second fan stage |
| 106.05 °C | active | third fan stage |
| 107.05 °C | active | fourth fan stage |
| 109.05 °C | active | fifth fan stage |
| 110.05 °C | passive, hot, critical | throttle back, then emergency shutdown |

Separately and lower down, the CPU package carries Intel's own critical
temperature in silicon -- `coretemp` reports `temp1_crit` of 105 °C here --
where the part throttles itself no matter what the platform is doing.

**Userspace cannot disable any of it.** The zone has no cooling device bound and
its governor is `user_space`, so the kernel is not the thing acting on these
trips; the embedded controller is, and sysfs only reports what the EC will do.
Every `trip_point_*_temp` is mode 0444 -- read-only even to root -- so the
temperatures cannot be moved, and there is no attribute anywhere that turns the
EC's response off. Nothing in this tool tries.

## What the firmware protects, and what this tool does

The ladder is damage protection. It belongs to the EC, it reacts in
milliseconds, it cannot be switched off, and nothing here weakens it. What it
does not do is care whether the machine is pleasant: it will sit at 105 °C with
the fans at maximum indefinitely, because its only job is keeping the silicon
alive.

This tool protects nothing. It moves the power budget around inside the range
the firmware published, and the firmware keeps doing its job at the top of that
range regardless of what was asked for. Raising PL1 to 135 W does not make the
machine unsafe -- it makes it hot and loud sooner, and the ladder still catches
it. Picking a lower budget is a comfort, noise and battery decision, not a
safety one.

## Caveat: custom profile and CPU power limits

The kernel lists `custom` in `platform_profile_choices`, but writing it returns
`EINVAL` on this firmware (Legion Pro 5 16IAX10H, BIOS Q6CN79WW). Custom mode
appears to be reachable only from the **Fn+Q** hardware key, not from sysfs.

Since `ppt_pl1_spl` / `ppt_pl2_sppt` are only accepted in custom mode -- writes
return `EBUSY` otherwise -- **`cpu-limit` cannot currently be applied**. The
values remain readable, and `max-power` works normally. If you reach custom mode
with Fn+Q, `cpu-limit` should then work; reports welcome.

## What the firmware exposes

| Setting | sysfs | Range |
|---|---|---|
| Platform profile | `/sys/firmware/acpi/platform_profile` | low-power, balanced, performance, max-power, custom |
| Conservation mode | `VPC2004:*/conservation_mode` | 0/1 (~60% cap) |
| USB always-on | `VPC2004:*/usb_charging` | 0/1 |
| Fn lock | `VPC2004:*/fn_lock` | 0/1 |
| CPU PL1 | `firmware-attributes/.../ppt_pl1_spl` | [watts, with min/max/default](#the-budget-stays-inside-the-firmwares-own-published-range) (read-only in practice, see caveat) |
| CPU PL2 | `firmware-attributes/.../ppt_pl2_sppt` | [watts, with min/max/default](#the-budget-stays-inside-the-firmwares-own-published-range) (read-only in practice, see caveat) |
| EPP | `cpu*/cpufreq/energy_performance_preference` | power .. performance |
| Turbo | `intel_pstate/no_turbo` | 0/1 |
| Fan RPM | `hwmon/*/fan[12]_input` | read-only |

Note this machine has no `charge_control_end_threshold`; Lenovo uses
`conservation_mode` instead, which is why generic battery-threshold tooling
finds nothing here.

## Hyprland integration

See [docs/hyprland.md](docs/hyprland.md) for the floating window rule and keybind.
