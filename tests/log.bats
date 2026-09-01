#!/usr/bin/env bats
# The transaction log: an append-only record of every write, every guard action
# and every refusal, so "why is my machine in this state" always has an answer.

setup() {
  load helpers
  setup_test_environment
}

@test "a write is recorded with actor, setting, from, to and outcome" {
  run "$LENOVO_POWER" turbo off
  [ "$status" -eq 0 ]

  [ "$(log_field 1 actor)" = user ]
  [ "$(log_field 1 setting)" = turbo ]
  [ "$(log_field 1 from)" = on ]
  [ "$(log_field 1 to)" = off ]
  [ "$(log_field 1 outcome)" = applied ]
}

@test "each entry carries a timestamp" {
  run "$LENOVO_POWER" battery-cap on

  [[ $(log_field 1 ts) =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "reading a setting is never logged" {
  run "$LENOVO_POWER" turbo
  [ "$status" -eq 0 ]
  run "$LENOVO_POWER" status
  [ "$status" -eq 0 ]
  run "$LENOVO_POWER" cpu-limit
  [ "$status" -eq 0 ]

  [ -z "$(log_lines)" ]
}

@test "a write the kernel or permissions refuse is logged as failed" {
  chmod 444 "$LENOVO_POWER_SYSFS_ROOT/sys/bus/platform/devices/VPC2004:00/usb_charging"

  run "$LENOVO_POWER" usb-charging on
  [ "$status" -ne 0 ]

  [ "$(log_field 1 setting)" = usb-charging ]
  [ "$(log_field 1 outcome)" = failed ]
}

@test "a preset is logged as the preset actor, with the writes it makes" {
  run "$LENOVO_POWER" preset quiet
  [ "$status" -eq 0 ]

  [ "$(log_lines | grep -c '"actor":"preset"')" = "$(log_lines | wc -l)" ]
  [[ $(log_lines) == *'"setting":"profile","from":"balanced","to":"low-power"'* ]]
  [[ $(log_lines) == *'"setting":"epp"'* ]]
  [[ $(log_lines) == *'"setting":"turbo"'* ]]
  [ "$(log_field '$' setting)" = preset ]
  [ "$(log_field '$' to)" = quiet ]
}

@test "every value written is one the log can round-trip without escaping" {
  run "$LENOVO_POWER" epp power

  [[ $(log_lines) != *'\'* ]]
  [ "$(log_lines | wc -l)" -eq 1 ]
}

@test "the log is trimmed once it reaches its ceiling of 5,000 entries" {
  seed_log 4999

  run "$LENOVO_POWER" turbo off

  [ "$(log_lines | wc -l)" -eq 4000 ]
}

@test "trimming keeps the newest entries and drops the oldest" {
  seed_log 4999

  run "$LENOVO_POWER" turbo off

  [[ $(log_lines) != *seed-1\"* ]]
  [[ $(log_lines) == *seed-4999* ]]
  [ "$(log_field '$' setting)" = turbo ]
}

@test "a log below the ceiling is left alone" {
  seed_log 10

  run "$LENOVO_POWER" turbo off

  [ "$(log_lines | wc -l)" -eq 11 ]
  [[ $(log_lines) == *seed-1\"* ]]
}
