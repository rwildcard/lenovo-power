#!/usr/bin/env bash
# Shared scaffolding for the suite. A test drives the real command against a fake
# hardware tree, with external commands stubbed and the state directory
# redirected, so it never writes to the real machine. (One test deliberately
# unsets the root to check the real sysfs paths are still the default; it only
# reads.)

LENOVO_POWER="$BATS_TEST_DIRNAME/../bin/lenovo-power"

# Write one fake hardware file, creating its directory. Paths are relative to
# the fake root, so they read like the real sysfs paths they stand in for.
fake_file() {
  local path="$LENOVO_POWER_SYSFS_ROOT/$1"
  mkdir -p "${path%/*}"
  printf '%s\n' "$2" >"$path"
}

# Read one back, for asserting on what a command wrote.
fake_value() { cat "$LENOVO_POWER_SYSFS_ROOT/$1"; }

# A Legion Pro 5 16IAX10H-shaped tree, including the globbed platform device,
# hwmon and per-CPU paths under the names the real kernel gives them.
setup_fake_hardware() {
  export LENOVO_POWER_SYSFS_ROOT="$BATS_TEST_TMPDIR/sysfs"

  fake_file sys/firmware/acpi/platform_profile balanced
  fake_file sys/firmware/acpi/platform_profile_choices \
    "low-power balanced performance max-power custom"

  local vpc=sys/bus/platform/devices/VPC2004:00
  fake_file "$vpc/conservation_mode" 0
  fake_file "$vpc/usb_charging" 0
  fake_file "$vpc/fn_lock" 1

  local fwa=sys/class/firmware-attributes/lenovo-wmi-other-0/attributes
  fake_file "$fwa/ppt_pl1_spl/current_value" 55
  fake_file "$fwa/ppt_pl1_spl/min_value" 50
  fake_file "$fwa/ppt_pl1_spl/max_value" 135
  fake_file "$fwa/ppt_pl1_spl/default_value" 55
  fake_file "$fwa/ppt_pl2_sppt/current_value" 65
  fake_file "$fwa/ppt_pl2_sppt/min_value" 60
  fake_file "$fwa/ppt_pl2_sppt/max_value" 210
  fake_file "$fwa/ppt_pl2_sppt/default_value" 65

  local cpu
  for cpu in cpu0 cpu1; do
    fake_file "sys/devices/system/cpu/$cpu/cpufreq/energy_performance_preference" \
      balance_performance
    fake_file "sys/devices/system/cpu/$cpu/cpufreq/energy_performance_available_preferences" \
      "default performance balance_performance balance_power power"
  done
  fake_file sys/devices/system/cpu/intel_pstate/no_turbo 0

  fake_file sys/class/power_supply/BAT0/capacity 61
  fake_file sys/class/power_supply/BAT0/status Discharging
  fake_file sys/class/power_supply/BAT0/power_now 12000000

  fake_file sys/class/hwmon/hwmon4/name coretemp
  fake_file sys/class/hwmon/hwmon4/temp1_label "Package id 0"
  fake_file sys/class/hwmon/hwmon4/temp1_input 53000
  fake_file sys/class/hwmon/hwmon7/name lenovo_wmi_other
  fake_file sys/class/hwmon/hwmon7/fan1_input 2100
  fake_file sys/class/hwmon/hwmon7/fan2_input 2300

  # A dGPU that is asleep, so a test never depends on the card being polled.
  local gpu=sys/bus/pci/devices/0000:01:00.0
  fake_file "$gpu/vendor" 0x10de
  fake_file "$gpu/class" 0x030000
  fake_file "$gpu/power/runtime_status" suspended
}

# Put a recording stub for COMMAND ahead of the real one on PATH. Every
# invocation appends its arguments to the command's recording; BODY, if given,
# is the stub's behaviour.
stub_command() {
  local name=$1 body=${2:-}
  mkdir -p "$STUB_DIR" "$STUB_LOG"
  cat >"$STUB_DIR/$name" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$STUB_LOG/$name"
$body
STUB
  chmod +x "$STUB_DIR/$name"
}

# What COMMAND was called with, one invocation per line; empty if never called.
stub_calls() { cat "$STUB_LOG/$1" 2>/dev/null; }

# Shadow every external command the CLI consults, so a test can never reach the
# real power-profiles daemon, GPU or sudo. Individual tests re-stub as needed.
setup_stubs() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$STUB_DIR" "$STUB_LOG"
  PATH="$STUB_DIR:$PATH"

  stub_command sudo 'echo "test tried to escalate: $*" >&2; exit 1'
  stub_command powerprofilesctl '
case "${1:-}" in
  list) printf "  performance:\n\n* balanced:\n\n  power-saver:\n\n" ;;
  get)  printf "balanced\n" ;;
esac
exit 0'
  stub_command omarchy-powerprofiles-set
  stub_command nvidia-smi
}

# Keep the transaction log, preset and anything else stateful out of the real
# home directory.
setup_state_dir() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$XDG_STATE_HOME"
}

setup_test_environment() {
  setup_fake_hardware
  setup_stubs
  setup_state_dir
}
