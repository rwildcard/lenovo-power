#!/usr/bin/env bats
# The monitor: warns while the machine is coping, and gives back the power
# budget it was told about once the machine stops coping.

setup() {
  load helpers
  setup_test_environment
}

# ------------------------------------------------------------- a single poll

@test "a poll on a cool machine reports the temperature against the thresholds" {
  fake_cpu_temp 54

  run "$LENOVO_POWER" monitor once

  [ "$status" -eq 0 ]
  [[ $output == *"54"* ]]
  [[ $output == *"95"* ]]
  [[ $output == *"100"* ]]
  [ -z "$(stub_calls notify-send)" ]
}

# ------------------------------------------------------------------- alerting

@test "sustained heat alerts, naming the temperature" {
  export LENOVO_POWER_ALERT_SUSTAIN=0
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once

  [ "$status" -eq 0 ]
  [[ $(stub_calls notify-send) == *96* ]]
}

@test "a spike shorter than the sustain window does not cry wolf" {
  export LENOVO_POWER_ALERT_SUSTAIN=3600
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ -z "$(stub_calls notify-send)" ]
}

@test "the sustained timer restarts when the machine cools back down" {
  export LENOVO_POWER_ALERT_SUSTAIN=3600
  fake_cpu_temp 96
  run "$LENOVO_POWER" monitor once
  [ -n "$(state_value alert_since)" ]

  fake_cpu_temp 60
  run "$LENOVO_POWER" monitor once

  [ -z "$(state_value alert_since)" ]
}

@test "repeat alerts are rate limited so a long hot session does not bury me" {
  export LENOVO_POWER_ALERT_SUSTAIN=0 LENOVO_POWER_ALERT_REPEAT=3600
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ "$(stub_calls notify-send | wc -l)" -eq 1 ]
}

@test "a further alert is sent once the repeat window has passed" {
  export LENOVO_POWER_ALERT_SUSTAIN=0 LENOVO_POWER_ALERT_REPEAT=0
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ "$(stub_calls notify-send | wc -l)" -eq 2 ]
}

@test "the machine is alerted about even when nothing was raised" {
  export LENOVO_POWER_ALERT_SUSTAIN=0
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once

  [ -z "$(state_value armed_profile)" ]
  [ -n "$(stub_calls notify-send)" ]
}

# ---------------------------------------------------------------- the guard

@test "the guard gives back a raised profile and latches" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = performance ]
  [ -n "$(state_value latched)" ]
  [ -z "$(state_value armed_profile)" ]
}

@test "the guard gives a raised CPU limit back to its recorded prior value" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  local pl1=sys/class/firmware-attributes/lenovo-wmi-other-0/attributes/ppt_pl1_spl/current_value
  run "$LENOVO_POWER" cpu-limit 135 --yes
  [ "$(fake_value $pl1)" = 135 ]
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$(fake_value $pl1)" = 55 ]
}

@test "the guard gives a raised GPU cap back to the card's default" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  fake_awake_gpu 40
  stub_permissive_sudo
  run "$LENOVO_POWER" gpu-limit 140 --yes
  [ -n "$(state_value armed_gpu)" ]
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [[ $(stub_calls nvidia-smi) == *"-pl 70.00"* ]]
  [ -z "$(state_value armed_gpu)" ]
}

@test "the guard reverses what was raised, not just the profile" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  local pl1=sys/class/firmware-attributes/lenovo-wmi-other-0/attributes/ppt_pl1_spl/current_value
  run "$LENOVO_POWER" cpu-limit 135 --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  # Nothing raised the profile, so the profile is left where it was.
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [ "$(fake_value $pl1)" = 55 ]
}

@test "the guard notifies, and says why the machine just got slower" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [[ $(stub_calls notify-send) == *101* ]]
  [[ $(stub_calls notify-send) == *performance* ]]
}

@test "guard actions are logged as the guard, not as me" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$(log_field '$' actor)" = guard ]
  [ "$(log_field '$' setting)" = profile ]
  [ "$(log_field '$' to)" = performance ]
}

@test "the guard stays put rather than restoring once the machine cools" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once

  fake_cpu_temp 55
  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ "$(fake_value sys/firmware/acpi/platform_profile)" = performance ]
  [ -n "$(state_value latched)" ]
}

@test "a hot machine with nothing raised has nothing to give back" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
  [ -z "$(state_value latched)" ]
}

@test "the guard waits for the temperature to be sustained" {
  export LENOVO_POWER_GUARD_SUSTAIN=3600
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
  [ -z "$(state_value latched)" ]
}

# -------------------------------------------------------------------- dGPU

@test "a suspended dGPU is never polled, so monitoring cannot wake it" {
  export LENOVO_POWER_ALERT_SUSTAIN=0
  fake_cpu_temp 96

  run "$LENOVO_POWER" monitor once

  [ -z "$(stub_calls nvidia-smi)" ]
}

@test "an awake dGPU near its thermal limit alerts in margin" {
  export LENOVO_POWER_ALERT_SUSTAIN=0
  fake_awake_gpu 3

  run "$LENOVO_POWER" monitor once

  [[ $(stub_calls nvidia-smi) == *temperature.gpu.tlimit* ]]
  [[ $(stub_calls notify-send) == *margin* ]]
}

@test "an awake dGPU with headroom to spare is left alone" {
  fake_awake_gpu 40

  run "$LENOVO_POWER" monitor once

  [ -z "$(stub_calls notify-send)" ]
}

@test "a card reporting no margin at all is not alerted about" {
  fake_awake_gpu "[N/A]"

  run "$LENOVO_POWER" monitor once

  [ "$status" -eq 0 ]
  [ -z "$(stub_calls notify-send)" ]
}

# ------------------------------------------------------------------- latching

@test "status shows when the guard is latched" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once

  fake_cpu_temp 55
  run "$LENOVO_POWER" status

  [[ $output == *"thermal guard"*"latched"* ]]
}

@test "status says nothing about the guard when it has not acted" {
  run "$LENOVO_POWER" status

  [[ $output != *"latched"* ]]
}

@test "deliberately raising a budget again clears the latch" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once
  [ -n "$(state_value latched)" ]

  fake_cpu_temp 55
  run "$LENOVO_POWER" profile max-power --yes

  [ -z "$(state_value latched)" ]
}

# ----------------------------------------------------------------- the loop

@test "the loop is the single poll, run repeatedly" {
  export LENOVO_POWER_GUARD_SUSTAIN=0 LENOVO_POWER_POLL_INTERVAL=1
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  "$LENOVO_POWER" monitor run >/dev/null 2>&1 &
  local pid=$! waited=0
  while [ -z "$(state_value latched)" ] && [ "$waited" -lt 50 ]; do
    sleep 0.1; waited=$((waited + 1))
  done
  kill "$pid" 2>/dev/null

  [ "$(fake_value sys/firmware/acpi/platform_profile)" = performance ]
}

@test "the guard's notification is not doubled by a hot alert at the same moment" {
  export LENOVO_POWER_GUARD_SUSTAIN=0 LENOVO_POWER_ALERT_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$(stub_calls notify-send | wc -l)" -eq 1 ]
  [[ $(stub_calls notify-send) == *"given back"* ]]
}

@test "an idle poll does not churn the state file every tick" {
  fake_cpu_temp 54

  run "$LENOVO_POWER" monitor once
  run "$LENOVO_POWER" monitor once

  [ ! -e "$XDG_STATE_HOME/lenovo-power/state" ]
}

@test "the guard's own log entries say which temperature caused them" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ "$(log_field '$' actor)" = guard ]
  [[ $(log_field '$' detail) == *101* ]]
}

@test "what the guard gave back reads as a list" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  run "$LENOVO_POWER" cpu-limit 135 --yes
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [[ $output == *"profile to performance, PL1 to 55 W"* ]]
}

@test "the guard will not wake a sleeping dGPU to give back its cap" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  fake_awake_gpu 40
  stub_permissive_sudo
  run "$LENOVO_POWER" gpu-limit 140 --yes
  [ -n "$(state_value armed_gpu)" ]

  # The card goes to sleep before the machine gets hot.
  fake_file sys/bus/pci/devices/0000:01:00.0/power/runtime_status suspended
  rm -f "$BATS_TEST_TMPDIR/calls/nvidia-smi"
  fake_cpu_temp 101

  run "$LENOVO_POWER" monitor once

  [ -z "$(stub_calls nvidia-smi)" ]
  # Still armed, so a later trigger can give it back once the card is up.
  [ -n "$(state_value armed_gpu)" ]
}

@test "a single poll says what the guard would do right now" {
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 60

  run "$LENOVO_POWER" monitor once

  [[ $output == *"the guard would"*"drop the profile to performance"* ]]
}

@test "a single poll on an unraised machine says there is nothing to give back" {
  run "$LENOVO_POWER" monitor once

  [[ $output == *"nothing"* ]]
}

@test "status says what the guard reversed, not merely that it latched" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  run "$LENOVO_POWER" cpu-limit 135 --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once

  fake_cpu_temp 55
  run "$LENOVO_POWER" status

  [[ $output == *latched* ]]
  [[ $output == *"profile to performance"* ]]
  [[ $output == *"PL1 to 55 W"* ]]
}

@test "a raise the hardware refuses leaves the latched summary intact too" {
  export LENOVO_POWER_GUARD_SUSTAIN=0
  run "$LENOVO_POWER" profile max-power --yes
  fake_cpu_temp 101
  run "$LENOVO_POWER" monitor once

  fake_cpu_temp 55
  chmod 444 "$LENOVO_POWER_SYSFS_ROOT/sys/firmware/acpi/platform_profile"
  run "$LENOVO_POWER" profile max-power --yes
  [ "$status" -ne 0 ]

  run "$LENOVO_POWER" status
  [[ $output == *"profile to performance"* ]]
}
