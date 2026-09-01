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
| CPU PL1 | `firmware-attributes/.../ppt_pl1_spl` | 50-135 W (read-only in practice, see caveat) |
| CPU PL2 | `firmware-attributes/.../ppt_pl2_sppt` | 60-210 W (read-only in practice, see caveat) |
| EPP | `cpu*/cpufreq/energy_performance_preference` | power .. performance |
| Turbo | `intel_pstate/no_turbo` | 0/1 |
| Fan RPM | `hwmon/*/fan[12]_input` | read-only |

Note this machine has no `charge_control_end_threshold`; Lenovo uses
`conservation_mode` instead, which is why generic battery-threshold tooling
finds nothing here.

## Hyprland integration

See [docs/hyprland.md](docs/hyprland.md) for the floating window rule and keybind.
