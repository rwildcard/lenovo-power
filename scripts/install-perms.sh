#!/usr/bin/env bash
# Grants the wheel group write access to the Lenovo power sysfs knobs, so
# lenovo-power works without sudo. Re-applied on every boot by a systemd unit.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }

GROUP=${LENOVO_POWER_GROUP:-wheel}
HELPER=/usr/local/lib/lenovo-power-perms
UNIT=/etc/systemd/system/lenovo-power-perms.service

install -d /usr/local/lib

cat >"$HELPER" <<'HELPEOF'
#!/usr/bin/env bash
# Relax ownership on the Lenovo/Legion power sysfs attributes so members of
# $GROUP can change them without root. Installed by lenovo-power.
set -uo pipefail
GROUP="${1:-wheel}"

grant() {
  for p in "$@"; do
    [[ -e $p ]] || continue
    chgrp "$GROUP" "$p" 2>/dev/null || continue
    chmod g+w "$p" 2>/dev/null || true
  done
}

# Platform profile (low-power / balanced / performance / max-power / custom)
grant /sys/firmware/acpi/platform_profile

# ideapad_laptop toggles: battery conservation, USB always-on charging, Fn lock
grant /sys/bus/platform/devices/VPC2004:*/conservation_mode \
      /sys/bus/platform/devices/VPC2004:*/usb_charging \
      /sys/bus/platform/devices/VPC2004:*/fn_lock

# lenovo_wmi_other CPU power limits (honoured in the 'custom' profile)
grant /sys/class/firmware-attributes/lenovo-wmi-other-*/attributes/*/current_value

# intel_pstate: per-core energy/performance preference and turbo boost
grant /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference \
      /sys/devices/system/cpu/intel_pstate/no_turbo
HELPEOF
chmod 755 "$HELPER"

cat >"$UNIT" <<UNITEOF
[Unit]
Description=Relax permissions on Lenovo power sysfs attributes
After=systemd-modules-load.service
ConditionPathExists=/sys/firmware/acpi/platform_profile

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HELPER $GROUP

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now lenovo-power-perms.service

echo
echo "Installed:"
echo "  $HELPER"
echo "  $UNIT  (enabled, group: $GROUP)"
echo
echo "Applied now and on every boot. Run 'lenovo-power status' to verify."
