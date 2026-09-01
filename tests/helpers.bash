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
  stub_command notify-send
  stub_command systemctl
}

# Put an awake dGPU in the fake tree, reporting MARGIN degrees of thermal
# headroom, so the monitor has a card worth polling.
fake_awake_gpu() {
  fake_file sys/bus/pci/devices/0000:01:00.0/power/runtime_status active
  mkdir -p "$STUB_DIR" "$STUB_LOG"
  cat >"$STUB_DIR/nvidia-smi" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$STUB_LOG/nvidia-smi"
case "\$*" in
  *temperature.gpu.tlimit*) echo '$1' ;;
  *power.default_limit*)    echo '70.00' ;;
  *)                        echo '140.00' ;;
esac
STUB
  chmod +x "$STUB_DIR/nvidia-smi"
}

# A sudo that runs the command instead of refusing it, for the few tests about
# what happens once a privileged write succeeds. Sudo's own flags are dropped
# first, so `sudo -n nvidia-smi ...` reaches nvidia-smi rather than exec.
stub_permissive_sudo() {
  stub_command sudo 'while [[ ${1:-} == -* ]]; do shift; done; exec "$@"'
}

# Keep the transaction log, preset and anything else stateful out of the real
# home directory.
setup_state_dir() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
}

setup_test_environment() {
  setup_fake_hardware
  setup_stubs
  setup_state_dir
}

# Fill the transaction log with N synthetic entries, numbered so a test can see
# which of them survived a trim.
seed_log() {
  local dir="$XDG_STATE_HOME/lenovo-power"
  mkdir -p "$dir"
  awk -v n="$1" 'BEGIN {
    for (i = 1; i <= n; i++)
      printf "{\"ts\":\"2026-01-01T00:00:00+00:00\",\"actor\":\"user\"," \
             "\"setting\":\"seed-%d\",\"from\":\"-\",\"to\":\"-\"," \
             "\"outcome\":\"applied\"}\n", i
  }' >"$dir/log.jsonl"
}

# The transaction log, as raw JSONL lines.
log_lines() { cat "$XDG_STATE_HOME/lenovo-power/log.jsonl" 2>/dev/null; }

# One field of one log line. LINE is a sed address, so 1 is the first entry and
# $ the most recent.
log_field() {
  local line
  line=$(log_lines | sed -n "$1p")
  [[ $line =~ \"$2\":\"([^\"]*)\" ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}

# Run the CLI on a pseudo-terminal, answering its prompt with REPLY, so a test
# with no terminal of its own can still exercise the interactive gate. The
# terminal echoes and ends lines with CR, neither of which is behaviour worth
# asserting on, so both are stripped.
run_on_tty() {
  local reply=$1 cmd out rc; shift
  printf -v cmd '%q ' "$LENOVO_POWER" "$@"
  # Captured rather than piped straight into tr, so the exit status is the
  # command's own and not the tidying that follows it.
  out=$(printf '%s\n' "$reply" | script -qec "$cmd" /dev/null); rc=$?
  printf '%s\n' "$out" | tr -d '\r'
  return $rc
}

# Set the fake CPU package temperature, in whole degrees C.
fake_cpu_temp() { fake_file sys/class/hwmon/hwmon4/temp1_input "$(( $1 * 1000 ))"; }

# What the state file records under KEY, or empty if it records nothing.
state_value() {
  awk -F'\t' -v k="$1" '$1 == k { print $2 }' \
    "$XDG_STATE_HOME/lenovo-power/state" 2>/dev/null
}
