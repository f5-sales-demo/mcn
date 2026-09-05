MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="===============xcsh-smsv2=="

--===============xcsh-smsv2==
Content-Type: text/cloud-boothook; charset="us-ascii"

#!/bin/sh
set -eu
SLI_MAC="${sli_mac}"
mkdir -p /etc/dhcp/dhclient-enter-hooks.d
cat >/etc/dhcp/dhclient-enter-hooks.d/99-xcsh-sli-never-default <<'EOF'
case "$${interface:-}" in
  "") ;;
  *)
    current_mac=$(cat "/sys/class/net/$${interface}/address" 2>/dev/null || true)
    if [ "$${current_mac}" = "${sli_mac}" ]; then
      unset new_routers
      unset new_classless_static_routes
      unset new_static_routes
    fi
    ;;
esac
EOF
chmod 600 /etc/dhcp/dhclient-enter-hooks.d/99-xcsh-sli-never-default
for interface_path in /sys/class/net/*; do
  [ "$(cat "$${interface_path}/address" 2>/dev/null || true)" = "$SLI_MAC" ] || continue
  interface=$${interface_path##*/}
  ip -4 route del default dev "$interface" 2>/dev/null || true
done

--===============xcsh-smsv2==
Content-Type: text/cloud-config; charset="us-ascii"

${site_cloud_init}

--===============xcsh-smsv2==--
