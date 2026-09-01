#!/usr/bin/env bats
# The hardware root: every sysfs path the CLI touches hangs off it, so a test
# can stand a whole machine up in a temporary directory.

setup() {
  load helpers
  setup_test_environment
}

@test "status reports the profile from the fake hardware tree" {
  fake_file sys/firmware/acpi/platform_profile max-power

  run "$LENOVO_POWER" status

  [ "$status" -eq 0 ]
  [[ $output == *"platform profile   max-power"* ]]
}

@test "profile writes the new profile into the fake platform_profile file" {
  run "$LENOVO_POWER" profile max-power

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = max-power ]
}

@test "the globbed platform device path resolves under the root" {
  run "$LENOVO_POWER" battery-cap on

  [ "$status" -eq 0 ]
  [ "$(fake_value sys/bus/platform/devices/VPC2004:00/conservation_mode)" = 1 ]
}

@test "the globbed hwmon path resolves under the root" {
  fake_file sys/class/hwmon/hwmon7/fan1_input 3900
  fake_file sys/class/hwmon/hwmon7/fan2_input 4100

  run "$LENOVO_POWER" status

  [ "$status" -eq 0 ]
  [[ $output == *"fans               3900 / 4100 rpm"* ]]
}

@test "a write under a fake root is refused rather than escalated to sudo" {
  chmod a-w "$LENOVO_POWER_SYSFS_ROOT/sys/firmware/acpi/platform_profile"

  run "$LENOVO_POWER" profile max-power

  [ "$status" -ne 0 ]
  [ -z "$(stub_calls sudo)" ]
  [ "$(fake_value sys/firmware/acpi/platform_profile)" = balanced ]
}

@test "the root defaults to empty, so an unset root reads real sysfs" {
  fake_file sys/firmware/acpi/platform_profile fake-only-profile
  unset LENOVO_POWER_SYSFS_ROOT

  run "$LENOVO_POWER" status
  [ "$status" -eq 0 ]

  # Whatever it read, it was not the tree we just built.
  [[ $output != *fake-only-profile* ]]

  # And on a machine that has the real attribute, it is that file's value.
  [ -r /sys/firmware/acpi/platform_profile ] || skip "no platform_profile here"
  [[ $output == *"platform profile   $(cat /sys/firmware/acpi/platform_profile)"* ]]
}
