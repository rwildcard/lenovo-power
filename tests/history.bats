#!/usr/bin/env bats
# `history` renders the transaction log for a human: aligned columns, oldest
# first, so a run of changes reads top to bottom.

setup() {
  load helpers
  setup_test_environment
}

@test "history renders a logged change as aligned columns under a header" {
  run "$LENOVO_POWER" turbo off

  run "$LENOVO_POWER" history

  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "TIME"*"ACTOR"*"SETTING"*"FROM"*"TO"*"OUTCOME"* ]]
  [[ ${lines[1]} == *"user"*"turbo"*"on"*"off"*"applied"* ]]
}

@test "the columns line up across entries of differing width" {
  run "$LENOVO_POWER" epp balance_power
  run "$LENOVO_POWER" turbo off

  run "$LENOVO_POWER" history

  local header=${lines[0]} first=${lines[1]} second=${lines[2]}
  [ "${header%%OUTCOME*}" = "${header%%OUTCOME*}" ]
  # The outcome word starts at the same column on every row.
  local col=${header%%OUTCOME*}
  [ "${first:${#col}:7}" = applied ]
  [ "${second:${#col}:7}" = applied ]
}

@test "history shows the oldest entry first and the newest last" {
  run "$LENOVO_POWER" battery-cap on
  run "$LENOVO_POWER" fn-lock off

  run "$LENOVO_POWER" history

  [[ ${lines[1]} == *battery-cap* ]]
  [[ ${lines[2]} == *fn-lock* ]]
}

@test "history takes a count and shows only the most recent entries" {
  run "$LENOVO_POWER" battery-cap on
  run "$LENOVO_POWER" usb-charging on
  run "$LENOVO_POWER" fn-lock off

  run "$LENOVO_POWER" history 1

  [ "${#lines[@]}" -eq 2 ]
  [[ ${lines[1]} == *fn-lock* ]]
}

@test "history renders the detail of an entry that carries one" {
  run "$LENOVO_POWER" battery-cap on
  printf '%s\n' \
    '{"ts":"2026-09-01T14:30:00-04:00","actor":"guard","setting":"profile","from":"max-power","to":"performance","outcome":"applied","detail":"CPU 101 C for 60s"}' \
    >>"$XDG_STATE_HOME/lenovo-power/log.jsonl"

  run "$LENOVO_POWER" history

  [[ $output == *"guard"* ]]
  [[ $output == *"CPU 101 C for 60s"* ]]
}

@test "history says so plainly when nothing has been recorded yet" {
  run "$LENOVO_POWER" history

  [ "$status" -eq 0 ]
  [[ $output == *"no history"* ]]
}

@test "history is itself a read, so it does not add to the log" {
  run "$LENOVO_POWER" turbo off
  run "$LENOVO_POWER" history

  [ "$(log_lines | wc -l)" -eq 1 ]
}

@test "history defaults to the twenty most recent entries" {
  local i
  for i in $(seq 1 12); do
    run "$LENOVO_POWER" turbo off
    run "$LENOVO_POWER" turbo on
  done
  [ "$(log_lines | wc -l)" -eq 24 ]

  run "$LENOVO_POWER" history

  [ "${#lines[@]}" -eq 21 ]
}
