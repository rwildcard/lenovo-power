#!/usr/bin/env bats
# Installing the monitor is a deliberate act of its own: nothing starts sending
# notifications until it is asked for.

setup() {
  load helpers
  setup_test_environment
  UNIT="$XDG_CONFIG_HOME/systemd/user/lenovo-power-monitor.service"
}

@test "install-monitor writes a user unit that runs the polling loop" {
  run "$LENOVO_POWER" install-monitor

  [ "$status" -eq 0 ]
  [ -f "$UNIT" ]
  [[ $(cat "$UNIT") == *"monitor run"* ]]
}

@test "the unit is a user service, so enabling it needs no root" {
  run "$LENOVO_POWER" install-monitor

  [[ $(stub_calls systemctl) == *"--user"* ]]
  [[ $(stub_calls systemctl) != *sudo* ]]
  [ -z "$(stub_calls sudo)" ]
}

@test "install-monitor enables and starts the service" {
  run "$LENOVO_POWER" install-monitor

  [[ $(stub_calls systemctl) == *"daemon-reload"* ]]
  [[ $(stub_calls systemctl) == *"enable"*"lenovo-power-monitor"* ]]
}

@test "the thresholds live in the unit, so they can be tuned without editing the tool" {
  run "$LENOVO_POWER" install-monitor

  local unit; unit=$(cat "$UNIT")
  [[ $unit == *"LENOVO_POWER_ALERT_TEMP=95"* ]]
  [[ $unit == *"LENOVO_POWER_ALERT_SUSTAIN=30"* ]]
  [[ $unit == *"LENOVO_POWER_ALERT_REPEAT=600"* ]]
  [[ $unit == *"LENOVO_POWER_GUARD_TEMP=100"* ]]
  [[ $unit == *"LENOVO_POWER_GUARD_SUSTAIN=60"* ]]
  [[ $unit == *"LENOVO_POWER_GPU_MARGIN=5"* ]]
}

@test "the unit points at a lenovo-power that exists" {
  run "$LENOVO_POWER" install-monitor

  local exec; exec=$(sed -n 's/^ExecStart=//p' "$UNIT")
  [ -x "${exec%% monitor run}" ]
}

@test "no other command enables the service, so the monitor is opt-in" {
  run "$LENOVO_POWER" status
  run "$LENOVO_POWER" profile max-power --yes
  run "$LENOVO_POWER" monitor once

  [ ! -f "$UNIT" ]
  [ -z "$(stub_calls systemctl)" ]
}
