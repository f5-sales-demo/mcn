#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if rg -n 'dynamic "(site_local_(inside_)?network|default_(os|sw)_version)"' terraform coverage/smsv2; then
  fail "GRE payload role still uses an empty dynamic block"
fi

rg -q 'site_local_network[[:space:]]*=[[:space:]]*each\.value\.payload_role == "slo" \? \{\} : null' terraform/aws_tgw_connect.tf ||
  fail "GRE SLO payload role is not a nullable object attribute"
rg -q 'site_local_inside_network[[:space:]]*=[[:space:]]*each\.value\.payload_role == "sli" \? \{\} : null' terraform/aws_tgw_connect.tf ||
  fail "GRE SLI payload role is not a nullable object attribute"

markers=(
  site_local_network site_local_inside_network dhcp_client disable_ha block_all_services
  no_network_policy no_forward_proxy f5_proxy no_proxy_bypass logs_streaming_disabled
  no_s2s_connectivity_sli no_s2s_connectivity_slo disable_url_categorization
  disable_management_network no_tls use_default_port round_robin no_challenge
  user_id_client_ip disable_waf disable_rate_limit disable_api_discovery
  disable_api_testing disable_api_definition
  service_policies_from_namespace disable_trust_client_ip_headers
  disable_malicious_user_detection disable_malware_protection disable_threat_mesh
  default_sensitive_data_policy f5_dns_default f5_ntp_default default_config
  default_sli_config no_offline_survivability_mode jumbo_disabled geo_proximity
  default_os_version default_sw_version disable_internet_vip local_address
  disable_v6 passive_mode_disabled bfd_disabled no_ipv4_address no_ipv6_address
  monitor monitor_disabled site_to_site_connectivity_interface_disabled
  site_to_site_connectivity_interface_enabled dns ssh web_user_interface enable_ha
  no_static_routes no_v6_static_routes use_slo_sli no_site_mesh_group
  sm_connection_public_ip enable_offline_survivability_mode jumbo_enabled no_jumbo jumbo
  disable_upgrade_drain disable_vega_upgrade_mode enable_vega_upgrade_mode
)

for marker in "${markers[@]}"; do
  if rg -n "^[[:space:]]*${marker}[[:space:]]*\\{[[:space:]]*\\}[[:space:]]*$" terraform coverage/smsv2; then
    fail "${marker} still uses removed empty-block syntax"
  fi
done

printf 'PASS: SMSv2 empty choices use nullable object attributes\n'
