#!/usr/bin/env bats
# What `status` reports, asserted against sensors a test can set.

setup() {
  load helpers
  setup_test_environment
}

@test "status shows the CPU package temperature from coretemp" {
  fake_file sys/class/hwmon/hwmon4/temp1_input 81500

  run "$LENOVO_POWER" status

  [ "$status" -eq 0 ]
  [[ $output == *"temperature        82 °C"* ]]
}

@test "status shows a placeholder when coretemp has no package sensor" {
  local coretemp=sys/class/hwmon/hwmon4
  rm "$LENOVO_POWER_SYSFS_ROOT/$coretemp/temp1_label" \
     "$LENOVO_POWER_SYSFS_ROOT/$coretemp/temp1_input"
  fake_file "$coretemp/temp2_label" "Core 0"
  fake_file "$coretemp/temp2_input" 62000

  run "$LENOVO_POWER" status

  [ "$status" -eq 0 ]
  [[ $output == *"temperature        n/a"* ]]
}

@test "status shows a placeholder when coretemp is absent" {
  rm -r "$LENOVO_POWER_SYSFS_ROOT/sys/class/hwmon/hwmon4"

  run "$LENOVO_POWER" status

  [ "$status" -eq 0 ]
  [[ $output == *"temperature        n/a"* ]]
}
