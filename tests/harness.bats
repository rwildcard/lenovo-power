#!/usr/bin/env bats
# The two seams the tool already had: external commands come from PATH, and the
# state directory comes from the environment. Both keep a test off the machine.

setup() {
  load helpers
  setup_test_environment
}

@test "external commands can be faked with a recording stub on PATH" {
  stub_command nvidia-smi 'printf "115.00, 35.00, 140.00\n"'

  run "$LENOVO_POWER" gpu-limit

  [ "$status" -eq 0 ]
  [ "$output" = "115.00 W (range 35.00-140.00)" ]
  [[ $(stub_calls nvidia-smi) == *"--query-gpu=enforced.power.limit,power.min_limit,power.max_limit"* ]]
}

@test "the state directory follows XDG_STATE_HOME" {
  run "$LENOVO_POWER" preset quiet
  [ "$status" -eq 0 ]

  [ "$(cat "$XDG_STATE_HOME/lenovo-power/preset")" = quiet ]

  run "$LENOVO_POWER" preset
  [ "$output" = quiet ]
}
