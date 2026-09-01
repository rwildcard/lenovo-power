#!/usr/bin/env bats
# The gate: every command that raises a power budget confirms first, and the
# confirmation is where the tool explains itself.

setup() {
  load helpers
  setup_test_environment
}

# ------------------------------------------------------------------ prompting

@test "raising the profile names the setting, the current value and the new one" {
  run run_on_tty n profile max-power

  [[ $output == *"platform profile"* ]]
  [[ $output == *balanced* ]]
  [[ $output == *max-power* ]]
  [[ $output == *"Apply?"* ]]
}

@test "the prompt says that this is not overclocking" {
  run run_on_tty n profile max-power

  [[ $output == *"not overclocking"* ]]
  [[ $output == *"thermal ladder"* ]]
}

@test "declining leaves the setting alone and logs the refusal" {
  run run_on_tty n profile max-power

  [ "$status" -ne 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [ "$(log_field 1 setting)" = profile ]
  [ "$(log_field 1 outcome)" = refused ]
}

@test "accepting applies the change" {
  run run_on_tty y profile max-power

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
  [ "$(log_field '$' outcome)" = applied ]
}

# ------------------------------------------------------------------- bypassing

@test "--yes applies without prompting, so a keybinding never hangs" {
  run "$LENOVO_POWER" profile max-power --yes

  [ "$status" -eq 0 ]
  [[ $output != *"Apply?"* ]]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
}

@test "with no terminal to confirm on, the raise is refused rather than applied" {
  run "$LENOVO_POWER" profile max-power

  [ "$status" -ne 0 ]
  [[ $output == *"no terminal"* ]]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [ "$(log_field 1 outcome)" = refused ]
}

# ---------------------------------------------------------------- hot refusal

@test "a CPU already at the guard trigger refuses the raise" {
  fake_cpu_temp 101

  run run_on_tty y profile max-power

  [ "$status" -ne 0 ]
  [[ $output == *101* ]]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [ "$(log_field 1 outcome)" = refused ]
}

@test "--yes does not override the hot refusal" {
  fake_cpu_temp 101

  run "$LENOVO_POWER" profile max-power --yes

  [ "$status" -ne 0 ]
  [[ $output == *"does not override"* ]]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
}

@test "the hot refusal follows the guard threshold, not a hardcoded number" {
  export LENOVO_POWER_GUARD_TEMP=70
  fake_cpu_temp 72

  run "$LENOVO_POWER" profile max-power --yes

  [ "$status" -ne 0 ]
  [[ $output == *"70"* ]]
}

@test "a CPU below the trigger raises normally" {
  fake_cpu_temp 99

  run "$LENOVO_POWER" profile max-power --yes

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
}

# ------------------------------------------------------- which commands gate

@test "profile custom is gated too" {
  run "$LENOVO_POWER" profile custom

  [ "$status" -ne 0 ]
  [[ $output == *"no terminal"* ]]
}

@test "cpu-limit is gated, and names both limits it is about to change" {
  run run_on_tty n cpu-limit 135 210

  [ "$status" -ne 0 ]
  [[ $output == *"PL1"*"55"*"135"* ]]
  [[ $output == *"PL2"*"65"*"210"* ]]
  [ "$(fake_value sys/class/firmware-attributes/lenovo-wmi-other-0/attributes/ppt_pl1_spl/current_value)" = 55 ]
}

@test "gpu-limit is gated" {
  stub_command nvidia-smi 'printf "70.00\n"'

  run "$LENOVO_POWER" gpu-limit 140

  [ "$status" -ne 0 ]
  [[ $output == *"no terminal"* ]]
  [ -z "$(stub_calls sudo)" ]
}

@test "the profiles the bar already switches are not gated" {
  run "$LENOVO_POWER" profile performance
  [ "$status" -eq 0 ]

  run "$LENOVO_POWER" profile low-power
  [ "$status" -eq 0 ]
}

@test "settings that do not raise a power budget are not gated" {
  run "$LENOVO_POWER" turbo on
  [ "$status" -eq 0 ]
  run "$LENOVO_POWER" epp performance
  [ "$status" -eq 0 ]
  run "$LENOVO_POWER" battery-cap on
  [ "$status" -eq 0 ]

  [[ $(log_lines) != *refused* ]]
}

# --------------------------------------------------------------- preset max

@test "preset max asks once up front and says it includes max-power" {
  run run_on_tty n preset max

  [ "$status" -ne 0 ]
  [[ $output == *"max-power"* ]]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
}

@test "preset max asks once, not again for the profile inside it" {
  run run_on_tty y preset max

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Apply?')" -eq 1 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
}

@test "preset max is refused when the CPU is hot, even with --yes" {
  fake_cpu_temp 101

  run "$LENOVO_POWER" preset max --yes

  [ "$status" -ne 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
}

@test "the presets that do not raise a power budget are not gated" {
  run "$LENOVO_POWER" preset work

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [[ $(log_lines) != *refused* ]]
}

# ------------------------------------------------------- arming for the guard

@test "the gate records the pre-raise profile so the guard can give it back" {
  run "$LENOVO_POWER" profile max-power --yes

  # The plan names the profile but never the value it was raised from: a
  # give-back goes to performance, so naming 'balanced' would promise a restore
  # that does not happen.
  run "$LENOVO_POWER" monitor once

  [[ $output == *"drop the profile to performance"* ]]
}

@test "the gate records the pre-raise CPU limits" {
  run "$LENOVO_POWER" cpu-limit 135 210 --yes

  run "$LENOVO_POWER" monitor once

  [[ $output == *"return PL1 to 55 W"* ]]
  [[ $output == *"return PL2 to 65 W"* ]]
}

@test "the gate records the pre-raise GPU cap" {
  stub_command nvidia-smi 'printf "70.00\n"'
  stub_permissive_sudo

  run "$LENOVO_POWER" gpu-limit 140 --yes
  [ "$status" -eq 0 ]

  # The armed set is the guard's, not the caller's, so ask the guard what it is
  # holding rather than reading the record it keeps.
  run "$LENOVO_POWER" monitor once

  [[ $output == *"dGPU cap"* ]]
}

@test "a raise the hardware refuses arms nothing, so the guard has nothing to undo" {
  chmod 444 "$LENOVO_POWER_SYSFS_ROOT/sys/firmware/acpi/platform_profile"

  run "$LENOVO_POWER" profile max-power --yes

  [ "$status" -ne 0 ]
  [ "$(log_field '$' outcome)" = failed ]

  run "$LENOVO_POWER" monitor once

  [[ $output == *"nothing"* ]]
}

@test "a raise the hardware refuses leaves the latch exactly as it found it" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once

  # The whole rendered line, so this covers the summary as well as the moment.
  run "$LENOVO_POWER" status
  local latched; latched=$(printf '%s\n' "$output" | grep "thermal guard")
  [ -n "$latched" ]

  fake_cpu_temp 55
  chmod 444 "$LENOVO_POWER_SYSFS_ROOT/sys/firmware/acpi/platform_profile"
  run "$LENOVO_POWER" profile max-power --yes
  [ "$status" -ne 0 ]

  run "$LENOVO_POWER" status

  [ "$(printf '%s\n' "$output" | grep "thermal guard")" = "$latched" ]
}

@test "a raise that is refused arms nothing" {
  run "$LENOVO_POWER" profile max-power
  [ "$status" -ne 0 ]

  run "$LENOVO_POWER" monitor once

  [[ $output == *"nothing"* ]]
}

@test "a refusal records what was being asked for, and why it was declined" {
  fake_cpu_temp 101

  run "$LENOVO_POWER" profile max-power --yes

  [ "$(log_field 1 setting)" = profile ]
  [ "$(log_field 1 from)" = balanced ]
  [ "$(log_field 1 to)" = max-power ]
  [ "$(log_field 1 outcome)" = refused ]
  [[ $(log_field 1 detail) == *"guard trigger"* ]]
}

@test "a refusal for want of a terminal records the same" {
  run "$LENOVO_POWER" cpu-limit 135

  [ "$(log_field 1 setting)" = cpu-limit ]
  [ "$(log_field 1 from)" = "55 W" ]
  [ "$(log_field 1 to)" = "135 W" ]
  [[ $(log_field 1 detail) == *terminal* ]]
}

@test "a preset that fails puts back the latch its first gate cleared" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" status
  local latched; latched=$(printf '%s\n' "$output" | grep "thermal guard")
  [ -n "$latched" ]

  # 'preset max' gates twice: once for the preset, once for the profile inside
  # it. Only the first of those found a latch, so only it has one to put back.
  fake_cpu_temp 55
  chmod 444 "$LENOVO_POWER_SYSFS_ROOT/sys/firmware/acpi/platform_profile"
  run "$LENOVO_POWER" preset max --yes

  run "$LENOVO_POWER" status
  [ "$(printf '%s\n' "$output" | grep "thermal guard")" = "$latched" ]
}

@test "the prompt shows the new value, not the armed-set key behind it" {
  run run_on_tty n cpu-limit 135 210

  [[ $output == *"135 W"* ]]
  [[ $output == *"210 W"* ]]
  [[ $output != *"|cpu_pl1"* ]]
  [[ $output != *"|cpu_pl2"* ]]
}
