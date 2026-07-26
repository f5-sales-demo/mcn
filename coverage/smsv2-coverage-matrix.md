# SMSv2 Coverage Matrix (xcsh_securemesh_site_v2)

Legend: ✅ done · ⏳ in progress · ⬜ not started · ➖ n/a · ⚠️ done with a documented caveat

Columns:

- **Structural** — the arm is expressible in HCL / present in the probe or module.
- **Validated** — an out-of-range / invalid value is rejected by input validation (`.tftest.hcl`).
- **Applied** — the arm applies live against the XC tenant (HTTP 200).
- **Idempotent** — a re-plan after apply reports "No changes".
- **Import-clean** — `terraform import` of the object re-plans with 0 changes.
- **Notes** — slice that covers the arm and any caveats.

> **Read the S8 completeness audit before quoting this table as "exhaustive."** The rows below are
> the arms the slices *worked*; they are not the resource. A mechanical enumeration of the
> `xcsh_securemesh_site_v2` schema finds **997 arms**, of which **312** are in scope for this probe
> and **143** are rendered by it. The other **169** are classified — covered elsewhere, excluded
> with a reason, or **still open** — in [S8 completeness audit](#s8-completeness-audit-provider-v3811)
> at the bottom of this file. Nothing here is evidence about an arm that has no row.

| Branch / leaf | Structural | Validated | Applied | Idempotent | Import-clean | Notes |
|---|---|---|---|---|---|---|
| azure.not_managed.node_list[].interface_list[] | ✅ | ⬜ | ✅ | ✅ | ✅ | iter-1 (live N=3) |
| interface_list.mtu (max 16384) | ✅ | ✅ | ✅ | ✅ | ✅ | S1: validator `AtMost(16384)` (reject 20000); base probe live-applied+idempotent; the leaf does not drift and the whole-object import re-plans 0-change (S7) |
| interface_list.priority (0-255) | ✅ | ✅ | ✅ | ✅ | ✅ | S1: validator `Between(0, 255)` (reject 256); on the base eth0 interface, live-applied+idempotent; whole-object import re-plans 0-change (S7) |
| vlan_interface.vlan_id (1-4095) | ✅ | ✅ | ⬜ | ➖ | ➖ | S1: validator `Between(1, 4095)` (reject 4096) proven at plan; NOT live-applicable — vlan_interface on the `azure` not_managed single Control node 400s (BAD_REQUEST); gated behind `var.extended_arms`, plan-validated only |
| custom_proxy.proxy_port (0-65535) | ✅ | ✅ | ⬜ | ➖ | ➖ | S1: validator `Between(0, 65535)` (reject 70000) proven at plan; NOT live-applicable — custom_proxy 400s on this probe; gated behind `var.extended_arms`, plan-validated only |
| ethernet_interface.mac | ✅ | ✅ | ✅ | ✅ | ✅ | S2: validator `MACValidator()` (reject `"not-a-mac"`); live-applied on the base eth0 with a valid MAC (`7C-1E-52-7F-F8-12`), idempotent; whole-object import re-plans 0-change (S7); gated by `string_arms` |
| static_ip.ip_address (CIDR) | ✅ | ✅ | ✅ | ✅ | ✅ | S2: validator `CIDRValidator()` (reject `"999.999.0.0/8"`); static_ip is the `dhcp_client` address-oneof sibling, live-applied+idempotent (`10.0.1.5/24`), gated by `string_arms`; whole-object import re-plans 0-change (S7) |
| static_ip.default_gw (IP) | ✅ | ✅ | ✅ | ✅ | ✅ | S2: validator `IPValidator()` (reject `"10.0.0.256"`); applied live with ip_address (`10.0.1.1`); whole-object import re-plans 0-change (S7) |
| local_vrf.sli_config.nameserver (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S2: `IPv4Validator()` (reject `"300.1.1.1"`) proven at plan; NOT live — `sli_config` is a distinct `local_vrf` oneof arm from `default_sli_config`, gated behind `vrf_string_arms`. **S8: its "live is an S3 concern" deferral was never honoured** — S3 did only the *interface* oneofs, so the `local_vrf` oneof stays open (S8 gaps L/M) |
| local_vrf.sli_config.vip (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S2: validator `IPv4Validator()` (reject the IPv6 literal `"2001:db8::1"`, proving IPv4-specificity); plan-validated only, gated behind `vrf_string_arms`. **S8: same never-honoured deferral as `nameserver` above** |
<!-- remaining toggle/interface/services arms seeded ⬜ for S3–S5 -->
| block_all_services{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1 (S0 probe) |
| disable_ha{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1 (S0 probe) |
| dns_ntp_config.f5_dns_default{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `custom_dns` covered in S4 (row below). Import-clean flipped in S8: this default arm was in the object on both S8 `perf_mode_l3_enhanced` probes, each of which imported and re-planned 0-change |
| dns_ntp_config.f5_ntp_default{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `custom_ntp` covered in S4 (row below). Import-clean flipped in S8, same evidence as `f5_dns_default` |
| local_vrf.default_config{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; the `slo_config` oneof sibling is still open (S8 gap L). Import-clean flipped in S8 (both l3 probes imported 0-change with this arm present) |
| local_vrf.default_sli_config{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; the `sli_config` oneof sibling is plan-only (rows above). Import-clean flipped in S8, same evidence |
| logs_streaming_disabled{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `log_receiver_with_net` is plan-only S4b. Import-clean flipped in S8, same evidence |
| no_forward_proxy{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `active_forward_proxy_policies` is plan-only S4b. Import-clean flipped in S8, same evidence |
| no_network_policy{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `active_enhanced_firewall_policies` is plan-only S4b. Import-clean flipped in S8, same evidence |
| no_s2s_connectivity_sli{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alt `dc_cluster_group_sli` is plan-only S4b. Import-clean flipped in S8, same evidence |
| no_s2s_connectivity_slo{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 probe; oneof alts `dc_cluster_group_slo` / `site_mesh_group_on_slo` covered in S4. Import-clean flipped in S8, same evidence |
| offline_survivability_mode.no_offline_survivability_mode{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 base arm; S5 `offline_arm=no_offline_survivability_mode` (default); defaults cycle apply→idempotent→import (0-change)→destroy; oneof alt: enable S5 |
| performance_enhancement_mode.perf_mode_l7_enhanced{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 base arm; S5 `perf_arm=perf_mode_l7_enhanced` (default); defaults cycle round-trip (0-change); carries its own jumbo sub-oneof since v3.80.0 (rows below); oneof alt: perf_mode_l3_enhanced S5 |
| re_select.geo_proximity{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 base arm; S5 `re_select_arm=geo_proximity` (default); defaults cycle round-trip (0-change); oneof alt: specific_re S5 |
| software_settings.os.default_os_version{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 base arm; S5 `os_arm=default_os_version` (default); defaults cycle round-trip (0-change); oneof alt: operating_system_version S5 |
| software_settings.sw.default_sw_version{} | ✅ | ➖ | ✅ | ✅ | ✅ | S0 base arm; S5 `sw_arm=default_sw_version` (default); defaults cycle round-trip (0-change); oneof alt: volterra_software_version S5 |
| node_list[].type (Control/Worker) | ✅ | ✅ | ✅ | ✅ | ✅ | iter-1 live; S2: validator `OneOf("Control", "Worker")` (reject `"Bogus"`); the valid `Worker` arm plans clean and `Control` applied live |
| interface_list.ethernet_interface{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1; block arm (its `mac` leaf → Validated ✅, row above); oneof vs vlan/dedicated S3 |
| interface_list.network_option.site_local_network{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1; empty marker, nothing to validate. **S8: the "oneof: SLI/inside S3" deferral was never honoured** — the `site_local_inside_network{}` sibling is still open (S8 gap P); S3 selected only `site_local_network`, so this oneof has one of two members covered |
| interface_list.dhcp_client{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1 + S3 `address_arm=dhcp_client`; block arm; the `static_ip` address-oneof sibling → Validated ✅ + Applied ✅ (rows above); live-applied+idempotent, whole-object import re-plans 0-change (S7) |
| labels (top-level metadata map) | ✅ | ➖ | ✅ | ✅ | ✅ | S7: `ignore_changes` removed; xcsh #1103 **and** #1244 are both fixed and released — neither is still an open blocker. #1286 preserves a config-declared `labels = {}` on read-back. **`length(var.labels) > 0 ? var.labels : null` is LOAD-BEARING — never reduce it to a bare `var.labels`** (see the S7 note). |
<!-- S3: interface / addressing oneof arms (enum selectors; live cycle uses -var extended_arms=false) -->
| interface_list.static_ip{} (address_choice) | ✅ | ✅ | ✅ | ✅ | ✅ | S3 `address_arm=static_ip` (default); ip_address/default_gw validated (rows above); live-applied+idempotent, whole-object import re-plans 0-change (S7) |
| interface_list.no_ipv4_address{} (address_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `address_arm=no_ipv4_address`; empty marker; live apply→idempotent→import (0-change)→destroy |
| interface_list.no_ipv6_address{} (ipv6_address_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `ipv6_arm=no_ipv6_address` (default); empty marker; live apply→idempotent→import (0-change)→destroy |
| interface_list.monitor{} (monitoring_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `monitor_arm=monitor`; empty marker; live apply→idempotent→import (0-change)→destroy |
| interface_list.monitor_disabled{} (monitoring_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `monitor_arm=monitor_disabled` (default); empty marker; live apply→idempotent→import (0-change)→destroy |
| interface_list.site_to_site_connectivity_interface_disabled{} | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `s2s_iface_arm=disabled` (default); empty marker; live apply→idempotent→import (0-change)→destroy |
| interface_list.site_to_site_connectivity_interface_enabled{} | ✅ | ➖ | ✅ | ✅ | ✅ | S3 `s2s_iface_arm=enabled`; empty marker; recon expected 400 (s2s wiring) but the single-node `azure` probe ACCEPTS it — live apply→idempotent→import (0-change)→destroy |
| interface_list.ethernet_interface{} (interface_choice) | ✅ | ✅ | ✅ | ✅ | ✅ | S3 `interface_arm=ethernet` (default); mac leaf validated (row above); live-applied+idempotent, whole-object import re-plans 0-change (S7) |
| interface_list.bond_interface{} (interface_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `interface_arm=bond`; plan-only — 400 (BAD_REQUEST) on single-node `azure` probe (confirmed live); `devices` `SizeBetween(1, 8)` reject proven at plan (reject-bond-devices); `lacp.rate` `Between(1, 30)` + `devices` plan clean |
| interface_list.vlan_interface{} (interface_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `interface_arm=vlan` (primary oneof); plan-only — 400 on single-node `azure` probe (confirmed live); `vlan_id` `Between(1, 4095)` validated (S1 reject-vlan-id via the extended_arms second interface) |
| interface_list.ipv6_auto_config{} (ipv6_address_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S3 `ipv6_arm=ipv6_auto_config`; plan-only — 400 on single-node IPv4 `azure` probe (confirmed live); renders the `host {}` autoconfig_choice member; plans clean |
| interface_list.static_ipv6_address{} (ipv6_address_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `ipv6_arm=static_ipv6_address`; plan-only — 400 on single-node IPv4 `azure` probe (confirmed live); `node_static_ip.ip_address` `CIDRValidator()` reject proven at plan (reject-static-ipv6) |
<!-- S4: networking / services top-level oneof arms (enum selectors; live cycle uses -var extended_arms=false) -->
| blocked_services.blocked_service{} (services_choice) | ✅ | ✅ | ✅ | ✅ | ✅ | S4 `services_arm=blocked_services`, live on provider v3.80.0 (S7): apply→idempotent→import (0-change)→destroy. The API read-back returns the configured entry, so the block genuinely round-trips. `network_type` `OneOf` reject proven at plan |
| blocked_services.blocked_service.network_type (OneOf) | ✅ | ✅ | ✅ | ✅ | ✅ | S4: validator `OneOf(VIRTUAL_NETWORK_*)` (reject `"BOGUS"`) proven at plan (reject-network-type); live-verified in S7 on both the default `VIRTUAL_NETWORK_SITE_LOCAL` and a non-default `VIRTUAL_NETWORK_SITE_LOCAL_INSIDE` — each echoed back unchanged |
| blocked_service.ssh{} (service_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S7 `blocked_service_arm=ssh` (default); empty marker; live apply→idempotent→import (0-change)→destroy; read-back returns `ssh` |
| blocked_service.dns{} (service_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S7 `blocked_service_arm=dns`; empty marker; live apply→idempotent→import (0-change)→destroy; read-back returns `dns` |
| blocked_service.web_user_interface{} (service_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S7 `blocked_service_arm=web_user_interface`; empty marker; live apply→idempotent→import (0-change)→destroy; read-back returns `web_user_interface` |
| f5_proxy{} (enterprise_proxy_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `proxy_arm=f5_proxy`; empty marker; live apply→idempotent→import (0-change)→destroy |
| custom_proxy.proxy_ip_address (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4: validator `IPv4Validator()` (reject `"999.1.1.1"`) proven at plan (reject-proxy-ip); custom_proxy 400s live (S1), gated behind `extended_arms`, plan-validated only |
| dns_ntp_config.custom_dns.dns_servers | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `dns_arm=custom_dns`; renders `dns_servers`; live apply→idempotent→import (0-change)→destroy |
| dns_ntp_config.custom_ntp.ntp_servers | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `ntp_arm=custom_ntp`; renders `ntp_servers`; live apply→idempotent→import (0-change)→destroy |
| custom_proxy_bypass.proxy_bypass | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `proxy_bypass_arm=custom_proxy_bypass`; renders `proxy_bypass` domain list; live apply→idempotent→import (0-change)→destroy |
| no_proxy_bypass{} (proxy_bypass_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `proxy_bypass_arm=no_proxy_bypass`; empty marker; live apply→idempotent→import (0-change)→destroy |
| enable_url_categorization{} (url_categorization_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `url_cat_arm=enable_url_categorization`; empty marker; live apply→idempotent→import (0-change)→destroy |
| disable_url_categorization{} (url_categorization_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `url_cat_arm=disable_url_categorization`; empty marker; live apply→idempotent→import (0-change)→destroy |
| disable_management_network{} (management_network_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `mgmt_net_arm=disable_management_network`; empty marker; live apply→idempotent→import (0-change)→destroy |
| load_balancing.vip_vrrp_mode (OneOf) | ✅ | ✅ | ✅ | ✅ | ✅ | S4 `vip_vrrp_mode=VIP_VRRP_ENABLE`/`VIP_VRRP_DISABLE`; validator `OneOf(VIP_VRRP_INVALID, VIP_VRRP_ENABLE, VIP_VRRP_DISABLE)` (reject `"BOGUS"`, reject-vip-vrrp-mode); both ENABLE and DISABLE live apply→idempotent→import (0-change)→destroy |
| site_mesh_group_on_slo{no_site_mesh_group{} sm_connection_public_ip{}} (s2s_slo_choice) | ✅ | ➖ | ✅ | ✅ | ✅ | S4 `s2s_slo_arm=site_mesh_group_empty`; renders both sub-oneofs (mesh_group_choice + connection_choice) all-empty; live apply→idempotent→import (0-change)→destroy |
| enable_ha{} (node_ha_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `ha_arm=enable_ha`; plan-only — 400 on single-node `azure` probe (needs >=3 nodes); plans clean |
| enable_management_network{} (management_network_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `mgmt_net_arm=enable_management_network`; plan-only — 400 on single-node `azure` probe; plans clean |
| active_forward_proxy_policies.forward_proxy_policies[] (ref) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `forward_proxy_arm=active_forward_proxy_policies`; plan-only — ObjectRefType list, ref-dependent; plans clean |
| active_enhanced_firewall_policies.enhanced_firewall_policies[] (ref) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `network_policy_arm=active_enhanced_firewall_policies`; plan-only — ObjectRefType list, ref-dependent; plans clean |
| log_receiver_with_net{log_receiver ref, use_slo_sli{}} (logs_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `logs_arm=log_receiver_with_net`; plan-only — ObjectRefType, ref-dependent; drives logs via `log_receiver_with_net`, NOT the stale top-level `log_receiver` field (provider #1256); plans clean |
| dc_cluster_group_sli{} (ref, s2s_sli_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_sli_arm=dc_cluster_group_sli`; plan-only — ObjectRefType, ref-dependent; plans clean |
| dc_cluster_group_slo{} (ref, s2s_slo_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_slo_arm=dc_cluster_group_slo`; plan-only — ObjectRefType, ref-dependent; plans clean |
| site_mesh_group_on_slo{site_mesh_group ref} (s2s_slo_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_slo_arm=site_mesh_group_ref`; plan-only — `site_mesh_group` ObjectRefType, ref-dependent; plans clean |
| segment_vrf.segment_config.nameserver (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4 `segment_vrf_arm=inline`; plan-only — needs a Segment object ref the provider cannot yet inject (specs #1053); validator `IPv4Validator()` (reject `"300.2.2.2"`, reject-segment-nameserver) proven at plan |
<!-- S5: site-mode oneof arms (perf / os / sw / offline / re_select / upgrade / admin; enum selectors; live cycle uses -var extended_arms=false) -->
| performance_enhancement_mode.perf_mode_l3_enhanced{} | ✅ | ➖ | ✅ | ✅ | ✅ | S5 `perf_arm=perf_mode_l3_enhanced`; carries its own jumbo sub-oneof, spelled DIFFERENTLY from the l7 pair (`jumbo`/`no_jumbo`, not `jumbo_enabled`/`jumbo_disabled`) — rows below; live apply→idempotent→import (0-change)→destroy |
| perf_mode_l3_enhanced.no_jumbo{} (jumbo sub-oneof) | ✅ | ➖ | ✅ | ✅ | ✅ | S8 `l3_jumbo_arm=no_jumbo` (default). S5 rendered this marker unconditionally; S8 made it a selector and re-verified live on v3.81.1: read-back `{"perf_mode_l3_enhanced":{"no_jumbo":{}}}`, apply→0-change re-plan→`state rm`→import→0-change plan→destroy |
| perf_mode_l3_enhanced.jumbo{} (jumbo sub-oneof) | ✅ | ➖ | ✅ | ✅ | ✅ | **S8, new** `l3_jumbo_arm=jumbo`; empty marker. Was the one unselected member of a covered oneof at the end of S7. Live on v3.81.1: read-back `{"perf_mode_l3_enhanced":{"jumbo":{}}}` (genuinely persisted, not defaulted), apply→0-change re-plan→`state rm`→import→0-change plan→destroy |
| perf_mode_l7_enhanced.jumbo_disabled{} (jumbo sub-oneof) | ✅ | ➖ | ✅ | ✅ | ✅ | S7 `l7_jumbo_arm=jumbo_disabled` (default); sub-oneof new in provider v3.80.0; the server materializes this marker, so declaring it is what keeps the object import-clean; live apply→idempotent→import (0-change)→destroy |
| perf_mode_l7_enhanced.jumbo_enabled{} (jumbo sub-oneof) | ✅ | ➖ | ✅ | ✅ | ✅ | S7 `l7_jumbo_arm=jumbo_enabled`; empty marker; live apply→idempotent→import (0-change)→destroy; read-back returns `jumbo_enabled` |
| software_settings.os.operating_system_version | ✅ | ✅ | ✅ | ✅ | ✅ | S5 `os_arm=operating_system_version` (`9.2024.6`); validator `LengthAtMost(20)` (reject 21-char, reject-os-version); create-only leaf — live apply→idempotent→import round-trips 0-change (0-change)→destroy |
| software_settings.sw.volterra_software_version | ✅ | ✅ | ✅ | ✅ | ✅ | S5 `sw_arm=volterra_software_version` (`crt-20250613-3382`); validator `LengthAtMost(20)` (reject 21-char, reject-sw-version); create-only leaf — live round-trips 0-change (0-change) |
| offline_survivability_mode.enable_offline_survivability_mode{} | ✅ | ➖ | ✅ | ✅ | ✅ | S5 `offline_arm=enable_offline_survivability_mode`; empty marker; live apply→idempotent→import (0-change)→destroy |
| upgrade_settings...enable_upgrade_drain{} (kubernetes_upgrade_drain) | ✅ | ✅ | ✅ | ✅ | ✅ | S5 `upgrade_drain_arm=enable_upgrade_drain`; recon expected 400 (k8s worker-drain on non-k8s node) but the single-node `azure` probe ACCEPTS it — reclassified live; renders drain leaves + `disable_vega_upgrade_mode{}`; apply→idempotent→import (0-change)→destroy |
| enable_upgrade_drain.drain_max_unavailable_node_count (1-5000) | ✅ | ✅ | ✅ | ✅ | ✅ | S5: `Between(1, 5000)`, upper reject 5001 (reject-drain-count); applied live via enable_upgrade_drain (default 1). **S8 closed the LOWER bound**: reject-drain-count-min pushes 0, so both bounds are asserted — a regression dropping the minimum used to pass |
| enable_upgrade_drain.drain_node_timeout (0-900) | ✅ | ✅ | ✅ | ✅ | ✅ | S5: validator `Between(0, 900)` (reject 901, reject-drain-timeout); applied live via enable_upgrade_drain (default 300) |
| enable_upgrade_drain.disable_vega_upgrade_mode{} (vega sub-oneof) | ✅ | ➖ | ✅ | ✅ | ✅ | S5 `vega_arm=disable_vega_upgrade_mode` (default); empty marker; applied live via enable_upgrade_drain; alt `enable_vega_upgrade_mode` plans clean |
| admin_user_credentials{ssh_key, admin_password clear_secret_info} | ✅ | ✅ | ⬜ | ➖ | ➖ | S5 `admin_creds=true`; plan-only — `[BAD_REQUEST]` 400 live on the single-node `azure` probe (recon expected live, reclassified); `ssh_key` `LengthAtMost(8192)` reject-proven at plan; dummy `string:///<base64>` secret (no real secret committed) |
| re_select.specific_re{primary_re, backup_re} | ✅ | ✅ | ⬜ | ➖ | ➖ | S5 `re_select_arm=specific_re`; plan-only — `[BAD_REQUEST] Invalid request parameters (status: 400)` live (primary_re must name a real RE geography); `primary_re` `LengthBetween(1, 64)` (reject 65-char, reject-primary-re) proven at plan |

**S1 notes (numeric-leaf input validation):**

- **How "Validated" is proven** — `coverage/smsv2/verify.sh` drives `terraform test` with a
  mocked `xcsh` provider (credential-free; the real schema validators still fire at plan — the
  version is whatever `terraform init` resolved against the floor in `coverage/smsv2/versions.tf`,
  the only tracked pin, and S8 removed the drifted per-file copies of that number).
  `validation.tftest.hcl` asserts valid bounds plan clean; `reject-tests/*.tftest.hcl`
  each push one leaf out of range and are *designed to fail* — `expect_failures` cannot capture
  provider schema validators (only user custom conditions), so verify.sh asserts the exact
  validator diagnostic per leaf instead. As of S8: 23 reject cases, 23 asserted diagnostics,
  counted by the script rather than restated in prose.
- **mtu is `AtMost(16384)` only** — the API's discontinuous rule {0} ∪ [512,16384] has no single
  minimum, so the failing test uses `mtu = 20000` (a small value like 200 is *not* rejected).
- **import caveat CLEARED (S7)** — the whole-object `terraform import` used to re-plan one
  in-place change, `- labels {}` on the interface. That is fixed in provider v3.77.5 (xcsh
  #1244 emits the import guards for the nested `interface_list.labels {}` marker). Re-verified
  live on v3.77.5: apply → plan "No changes" → `state rm` → `import` → plan **0 changes**, and
  again on v3.81.1 in S8. S8 confirmed the guard is load-bearing rather than defensive: the API
  read-back of a probe that never declares it returns `interface_list[0].labels: {}`, i.e. the
  server really does materialize the marker.
- **vlan_id / proxy_port not live-applied** — `vlan_interface` and top-level `custom_proxy` both
  return `[BAD_REQUEST] Invalid request parameters (400)` on the `azure` not_managed single Control
  node. They are gated behind `var.extended_arms` (default true) so their validators are reached
  at PLAN time; the live apply/idempotent/import ran with `-var extended_arms=false` on the base
  probe (which still carries the mtu and priority leaves).

**S2 notes (string-leaf input validation, provider >= 3.75.1):**

- **Same verify.sh harness** — the S2 string reject cases (`reject-mac`, `reject-ip-address`,
  `reject-default-gw`, `reject-nameserver`, `reject-vip`, `reject-node-type`) are driven by the
  same `verify.sh` Phase 2, which asserts each validator's exact diagnostic. The accept case in
  `validation.tftest.hcl` proves every string validator also passes a valid value at plan.
- **mac / static_ip live-applied** — unlike S1's vlan_interface/custom_proxy, the eth0
  `ethernet_interface.mac` and the `static_ip { ip_address, default_gw }` address-oneof arm both
  apply live (HTTP 200) on the `azure` not_managed single-node probe. The live cycle ran twice
  with a fresh `probe_name`: (a) the base arm `-var string_arms=false` (dhcp_client, no mac), and
  (b) the string arm `-var string_arms=true` (mac + static_ip) — both apply → 0-change re-plan →
  import → destroy 0-change on every step (the shared labels{} drift was cleared in S7) and no
  string-leaf drift.
- **nameserver / vip plan-only** — `IPv4Validator()` is proven at PLAN via `reject-nameserver`
  (bad IPv4 `300.1.1.1`) and `reject-vip` (the IPv6 literal `2001:db8::1`, proving IPv4-specificity).
  They live on `local_vrf.sli_config`, a distinct oneof arm from the base `default_sli_config`, so
  they are gated behind `var.vrf_string_arms` (default false) and NOT live-applied — the live oneof
  swap is an S3 concern. Not overclaimed: Applied stays ⬜.
- **validator string values** — MAC uses `net.ParseMAC`, CIDR `net.ParseCIDR`, IP `net.ParseIP`,
  IPv4 `net.ParseIP + To4()`; each skips null/empty (Optional) so absent leaves never error.

**S3 notes (interface / addressing oneof arms, provider v3.76.0):**

- **Enum selectors, not booleans** — each interface oneof is driven by an enum var
  (`interface_arm`, `address_arm`, `ipv6_arm`, `monitor_arm`, `s2s_iface_arm`) so exactly one
  member of each oneof renders and no two siblings coexist (which would trip `ConflictsWith`). The
  old S2 `string_arms` boolean now gates only the `mac` leaf; the address oneof is `address_arm`.
- **Live cycle uses `-var extended_arms=false`** — as in S1/S2, the default `extended_arms=true`
  second interface (vlan/custom_proxy) 400s, so every live apply/idempotent/import ran with
  `extended_arms=false` on the base probe (which still renders one member of every eth0 oneof).
- **Live-appliable arms** — `ethernet_interface`, `dhcp_client`, `static_ip`, `no_ipv4_address`,
  `no_ipv6_address`, `monitor`, `monitor_disabled`, `s2s_..._disabled`, `s2s_..._enabled` all
  apply (HTTP 200), re-plan clean, and import 0-change (the `labels {}` drift was cleared in S7). `s2s_..._enabled` was expected plan-only in recon but the
  single-node `azure` probe accepts it — reclassified live after verification.
- **Plan-only arms** — `bond_interface`, `vlan_interface`, `ipv6_auto_config`,
  `static_ipv6_address` each return `[BAD_REQUEST] Invalid request parameters (status: 400)` on the
  single-node `azure` not_managed probe (confirmed live), so their schema is proven at PLAN only via
  `validation.tftest.hcl` positive asserts, and their validated leaves via `verify.sh` reject tests
  (`reject-bond-devices` = `devices` `SizeBetween(1, 8)`, `reject-static-ipv6` = `node_static_ip`
  `ip_address` `CIDRValidator()`). `vlan_id` `Between(1, 4095)` reject is already covered by S1.
- **is_management / is_primary** — out of S3 scope (provider-capability gap, tracked in
  api-specs-enriched #1049; needs spec injection + regen).

**S4 notes (networking / services top-level oneof arms, provider v3.76.0):**

- **Enum selectors supersede the base literals** — each top-level networking/services oneof is driven
  by an enum var (`services_arm`, `ha_arm`, `dns_arm`, `ntp_arm`, `proxy_arm`, `proxy_bypass_arm`,
  `url_cat_arm`, `mgmt_net_arm`, `s2s_slo_arm`, `s2s_sli_arm`, `forward_proxy_arm`,
  `network_policy_arm`, `logs_arm`, `vip_vrrp_mode`, `segment_vrf_arm`) so exactly ONE member of each
  oneof renders. Every default is the arm the pre-S4 base probe already applied, so a bare
  `terraform plan` (all defaults) shows NO diff versus the pre-S4 base — verified live: applied the
  committed base, swapped in the S4 code, and a defaults plan reported "No changes."
- **Live cycle uses `-var extended_arms=false`** — as in S1–S3, `custom_proxy` and the second vlan
  interface 400 live, so every S4a live apply/idempotent/import ran with `extended_arms=false`.
- **S4a live-appliable arms** (HTTP 200, idempotent, import-clean): `f5_proxy`, `custom_dns`, `custom_ntp`, `custom_proxy_bypass`, `no_proxy_bypass`,
  `enable_url_categorization`, `disable_url_categorization`, `disable_management_network`,
  `load_balancing.vip_vrrp_mode` (ENABLE + DISABLE), `site_mesh_group_on_slo` all-empty
  (`no_site_mesh_group{} sm_connection_public_ip{}`), and — since S7 — `blocked_services`. Each ran
  apply→0-change re-plan→import→destroy.
- **`blocked_services` is live as of S7** — S4 had to reclassify it plan-only because the apply failed
  with `Provider produced inconsistent result after apply: .blocked_services.blocked_service block
  count changed from 1 to 0`. Root cause was provider #1257: the provider sent the JSON key
  `blocked_service` while F5's runtime key is the misspelled `blocked_sevice`, so the API ignored the
  block and the read-back found nothing. The wire-name contract (api-specs `x-f5xc-wire-name`, specs
  `v2.1.194`, provider `v3.80.0`) fixed it, and the arm now applies live — see the S7 notes for the
  read-back evidence.
- **S4b plan-only (ref-dependent)** — `active_forward_proxy_policies`,
  `active_enhanced_firewall_policies`, `log_receiver_with_net`, `dc_cluster_group_sli`,
  `dc_cluster_group_slo`, and `site_mesh_group_on_slo` with a `site_mesh_group` ref are ObjectRefType
  arms whose referents must pre-exist; their schema is proven at PLAN via `validation.tftest.hcl`
  positive asserts.
- **S4c plan-only (single-node 400)** — `enable_ha` and `enable_management_network` 400 on the
  single-node `azure` probe; proven at PLAN.
- **`segment_vrf` plan-only** — a live `segment_vrf` needs a Segment object reference the provider
  cannot yet inject (specs #1053); proven at PLAN, and its `segment_config.nameserver`
  `IPv4Validator()` reject at plan (reject-segment-nameserver, `"300.2.2.2"`).
- **Stale `log_receiver` avoided** — logs are driven via `log_receiver_with_net`, never the stale
  top-level `log_receiver` field (provider #1256).

**S5 notes (site-mode oneof arms, provider v3.76.0):**

- **Enum selectors supersede the base literals** — each site-mode oneof is driven by an enum var
  (`perf_arm`, `os_arm`/`os_version`, `sw_arm`/`sw_version`, `offline_arm`, `re_select_arm`,
  `upgrade_drain_arm`/`drain_max_unavailable`/`drain_node_timeout`/`vega_arm`, `admin_creds`) that
  replaces the pre-S5 hardcoded `performance_enhancement_mode`/`software_settings`/
  `offline_survivability_mode`/`re_select` literals, and adds gated `upgrade_settings` +
  `admin_user_credentials` blocks (both unset in the base). Every default renders the identical base
  member, so a bare `terraform plan` (all defaults) shows NO diff — verified live: defaults
  apply→0-change re-plan→import→destroy round-trips 0-change on every step.
- **S5a live-appliable** (HTTP 200, idempotent, import-clean):
  `perf_mode_l3_enhanced{no_jumbo{}}`, `operating_system_version` (`9.2024.6`),
  `volterra_software_version` (`crt-20250613-3382`), `enable_offline_survivability_mode`, and
  `upgrade_settings.kubernetes_upgrade_drain.enable_upgrade_drain` (drain count/timeout + vega). Each
  ran apply→0-change re-plan→import→destroy on the single-node probe.
- **`operating_system_version`/`volterra_software_version` are create-only** — the API forbids
  changing them after create, but the pinned values still import/re-plan 0-change (verified).
- **`enable_upgrade_drain` reclassified live** — recon expected a 400 (k8s worker-node drain on a
  non-k8s single node), but the single-node `azure` probe ACCEPTS it and round-trips clean (same
  surprise as S3 `s2s_..._enabled`). `disable_upgrade_drain` and `enable_vega_upgrade_mode` plan clean.
- **S5b plan-only (single-node 400)** — `admin_user_credentials` and `re_select.specific_re` each
  return `[BAD_REQUEST] Invalid request parameters (status: 400)` on the single-node probe (both were
  expected live in recon; reclassified after verification). `admin_user_credentials` needs the node
  local services / a multi-node CE; `re_select.specific_re.primary_re` must name a real RE geography
  (a dummy name 400s). Their validators are reject-proven at plan.
- **`admin_password` dummy secret** — the `admin_password` SecretType uses `clear_secret_info { url =
  "string:///<base64>" }` (the only dependency-free backend; blindfold/vault/wingman need external
  providers → 400) with a base64 of a throwaway placeholder. NO real secret is committed. The
  `secret_encoding_type` leaf S5 also covered **no longer exists**: the upstream F5 spec dropped it from
  SecretType, so provider v3.80.0 (specs v2.1.194) has no such attribute and its reject test is retired.
- **Provider enrichment gap #1258** — filed for the `enable_upgrade_drain.drain_node_timeout`
  required-ness (the arm inventory marks it required); the harness always supplies it (default 300).
  Not blocking — S5 is pure-mcn coverage (no provider/specs change).

**S7 notes (labels workaround retired, provider v3.77.5):**

- **`ignore_changes = [labels]` deleted** from `terraform/modules/xc-site/main.tf`. Its comment blamed the
  nested empty-marker class (#1103), but it targeted the **top-level metadata map** and was masking a
  different bug. Both are now fixed: xcsh #1244 (import guards for the nested `interface_list.labels {}`
  marker) and xcsh #1286 (a config-declared empty `labels = {}` survives the post-apply read-back).
- **The module sends `null`, not `{}`, when `var.labels` is empty.** #1286 fixes the post-apply half only —
  on import the state carries just id/name/namespace and `ReadRequest` exposes no config, so a literal `{}`
  still re-plans `+ labels = {}` on the first post-import plan (verified live). `null` avoids asking the
  provider to distinguish something it cannot observe.
- **Live proof (v3.77.5 from the registry, dev_overrides off, disposable probes only):**
  (a) `cov-probe-s7d1-01` defaults → apply → plan "No changes" → `state rm` → `import system/...` → plan
  **0 changes**, with no `ignore_changes` anywhere; (b) `cov-probe-s7d1-02` with `labels = {}` in config →
  apply → plan **"No changes"**. Both probes destroyed; the live demo sites were never touched.
- **Scope of the Import-clean flips.** The S7 import proof was re-run live on the base probe only. Every
  other arm's Import-clean cell is now `✅` because the sole caveat it carried was this one shared marker,
  and #1244's fix is resource-wide rather than arm-specific: regeneration guards **39 of 39** nested
  `labels` closures in `securemesh_site_v2_resource.go`. Arms whose S3/S4/S5 cycle already recorded a live
  `import (0-change)` are unchanged in meaning; the flip only removes the "modulo `labels {}`" caveat. No
  arm was re-applied live in S7 to re-observe its own import.

**S7 notes (`blocked_services` promoted to live, provider v3.80.0):**

- **The probe is pinned to `>= 3.80.0`** — the first release carrying the `x-f5xc-wire-name` contract
  (specs `v2.1.194`). `blocked_services` cannot round-trip on any earlier provider.
- **F5's runtime really does use the misspelled key.** Until now that claim rested on a code comment.
  The live read-back of `GET /api/config/namespaces/system/securemesh_site_v2s/<probe>` returns
  `spec.blocked_services.blocked_sevice[]` — the corrected `blocked_service` spelling is **not** what
  the API emits, so the wire-name mapping is load-bearing, not decorative. The Terraform-facing name
  stays `blocked_service` (`tfsdk` tag unchanged), so no HCL rename was needed.
- **`service_choice` keeps exactly ONE member.** The pre-S7 config set `ssh {}` *and*
  `web_user_interface {}` in the same `blocked_service`; the read-back came back with only `ssh`, and
  the provider's absent-marker suppression hid that silent drop behind a 0-change plan. The members are
  now an enum selector (`blocked_service_arm` = `dns` | `ssh` | `web_user_interface`) and each was
  live-cycled on its own: apply → 0-change re-plan → `state rm` → `import` → 0-change plan → destroy,
  with the read-back returning the configured member every time.
- **`network_type` round-trips on a non-default value too** — `VIRTUAL_NETWORK_SITE_LOCAL_INSIDE` was
  applied and echoed back unchanged, so the leaf is genuinely persisted rather than defaulted.
- **Two unrelated v3.80.0 schema deltas had to be absorbed** to keep the probe valid and import-clean at
  the pinned version: SecretType lost `secret_encoding_type` (see the S5 note), and
  `perf_mode_l7_enhanced` gained a `{jumbo_disabled | jumbo_enabled}` sub-oneof whose server-materialized
  `jumbo_disabled` marker re-planned as a removal after import until the config declared it
  (`l7_jumbo_arm`). Both are upstream spec changes, not probe defects.
- **Live proof (registry v3.80.0, `dev_overrides` off, disposable probes only):**
  `cov-probe-s7-bs-ssh-02`, `cov-probe-s7-bs-web-user-interface-02`, `cov-probe-s7-bs-dns-02`,
  `cov-probe-s7-nettype-inside-01`, `cov-probe-s7-jumbo-enabled-01` and `cov-probe-s7-defaults-01` each
  ran the full cycle and were destroyed. The live demo sites were never in state and never touched.

## S8 completeness audit (provider v3.81.1)

Every slice before this one grew the table row by row and never asked what was *missing*. S8 asks.

### Method (reproducible)

```bash
cd coverage/smsv2
printf 'provider_installation {\n  direct {}\n}\n' > /tmp/tfrc
TF_CLI_CONFIG_FILE=/tmp/tfrc terraform init -upgrade      # log must name the version you expect
TF_CLI_CONFIG_FILE=/tmp/tfrc terraform providers schema -json > /tmp/schema.json
# then walk resource_schemas["xcsh_securemesh_site_v2"].block recursively over
# .attributes and .block_types, emitting one dotted path per arm.
```

### Headline

| Measure | Count |
|---|---|
| Arms in the `xcsh_securemesh_site_v2` schema at v3.81.1 (415 attributes + 582 blocks) | 997 |
| Out of scope: the 10 non-`azure` site-provider subtrees, 68 arms each | 680 |
| Out of scope: the Terraform `timeouts` meta-block | 5 |
| **In scope for this probe** | **312** |
| Rendered by `coverage/smsv2/main.tf` | 143 |
| **Not rendered — classified below** | **169** |

The 11 site-provider subtrees (`aws`, `azure`, `baremetal`, `equinix`, `gcp`, `kvm`, `nutanix`,
`oci`, `openshift_virtualization`, `openstack`, `vmware`) were verified **byte-identical** modulo
the top-level key: dumping each subtree with its prefix rewritten to `SITE` and `diff`-ing against
`azure` gives no differences for all ten. They come from one generated code path, so the `azure`
rows describe their structure too — but only `azure` is live-verified, and nothing here claims a
CE was ever booted on AWS or vSphere.

### Gap classification

Not covered, and why. "Still open" means exactly that: no arm below has been quietly downgraded
to "excluded" to make the table look finished.

| # | Family | Arms | Class | Reason / evidence |
|---|---|---|---|---|
| A | `id` | 1 | ➖ n/a | Computed Terraform identifier, not an API arm. |
| B | `annotations`, `description`, `disable` | 3 | ⚠️ partial | `description` **is** applied live by the production module (`terraform/modules/xc-site/main.tf`), just not by this probe, and has no validator anywhere. `annotations`/`disable` are **still open**: S8 saw the server materialize `metadata.annotations: {}` unprompted, so a literal `{}` is an untested drift source. |
| C | `tunnel_type`, `tunnel_dead_timeout` | 2 | ⬜ still open | Both `Optional + Computed`; S8 saw the server materialize them (`SITE_TO_SITE_TUNNEL_IPSEC_OR_SSL` / `0`) on a probe declaring neither. Computed absorbs the default — which is exactly why 8 slices missed them: undeclared, they cannot drift. Never *set* from config, so no round-trip evidence. |
| D | `enable_advanced_delivery{}` / `disable_advanced_delivery{}` | 2 | ⬜ still open | A whole top-level oneof with no row in any slice. S8 evidence: neither key appears in the read-back of a live site, so unlike C the server does **not** default it — it is genuinely unexercised, not merely invisible. |
| E | `enable_log_anonymization{}` / `disable_log_anonymization{}` | 2 | ⬜ still open | Same as D: a whole top-level oneof, absent from the read-back, never rendered. |
| F | `.tenant` on every ObjectRefType | 12 | ⬜ still open | Not excluded, just untested. Every arm carrying one is itself plan-only (ref-dependent), so a `tenant` round-trip could not have been observed even incidentally. A cross-tenant ref is the only thing that would exercise it. |
| G | `SecretType.blindfold_secret_info{...}` (×2 sites) | 8 | ➖ excluded | Needs an offline Blindfold seal plus a real decryption/store provider. Sealing is non-deterministic, so an inline seal drifts on every plan; the seal must be done once and pinned. The probe deliberately uses `clear_secret_info`, the only dependency-free backend — `vault`/`wingman` 400 for the same reason. |
| H | `clear_secret_info.provider_ref` (×2 sites) | 2 | ⬜ still open | The `url` sibling is covered; `provider_ref` names a secret-management provider object that must pre-exist. Same class as F. |
| I | `custom_proxy.username`, `.password{...}`, `{enable,disable}_re_tunnel{}` | 6 | ⬜ still open at plan | `custom_proxy` itself returns `[BAD_REQUEST] 400` on the single-node `azure` probe, so nothing under it can be live. But its `proxy_ip_address`/`proxy_port` leaves *are* plan-asserted and these are not — there is no reason they could not be. |
| J | `static_routes` / `static_v6_routes` under `local_vrf.{sli,slo}_config` and `segment_vrf.segment_config` | 84 | ⬜ still open | **Largest single gap: 27% of the in-scope surface.** Six instances of one identical `SiteStaticRoutesListType`. Even the `no_static_routes{}` empty siblings are unrendered. One selector on one instance covers all six. |
| K | `interface_list.ipv6_auto_config.router{...}` | 21 | ⬜ still open | The probe renders only the `host{}` member of `autoconfig_choice`. The `router` member carries `network_prefix`, a `dns_config` oneof, and a `stateful` DHCPv6 subtree with pools. `ipv6_auto_config` as a whole is already plan-only (400 on a single-node IPv4 probe), so this is a plan-level gap. |
| L | `local_vrf.slo_config{...}` | 7 | ⬜ still open | The SLO counterpart of `sli_config`. The probe always selects the `default_config{}` empty marker, so this member of the oneof has never been rendered — not even at plan. |
| M | `local_vrf.sli_config` unwired leaves (`secondary_nameserver`, `labels{}`, `no_static_routes{}`, `no_v6_static_routes{}`) | 4 | ⬜ still open | `sli_config` renders only `nameserver` + `vip`, for their IPv4 validators. |
| N | `segment_vrf.segment_config.secondary_nameserver` | 1 | ⬜ still open | Sibling of the covered `nameserver`; `segment_vrf` is plan-only regardless. |
| O | `bond_interface.{name, link_polling_interval, link_up_delay}`, `.active_backup{}` | 4 | ⬜ still open | `active_backup{}` is the unselected member of the bond mode oneof (`lacp` is covered). `bond_interface` is plan-only (400), so this is a plan-level gap. |
| P | Unselected members of covered oneofs: `site_local_inside_network{}`, `use_management_network{}`, `sm_connection_pvt_ip{}`, `cluster_static_ip{}` (+ `interface_ip_map{}`) | 6 | ⬜ still open | The most misleading class: every *sibling* is ✅. SLI `site_local_inside_network` is the notable one — its row promised it as "S3" and S3 never did it. `perf_mode_l3_enhanced.jumbo{}` sat here until S8. |
| Q | `interface_list.description_spec`, `interface_list.labels{}`, `node_static_ip.default_gw`, `node_list.public_ip` | 4 | ⚠️ mixed | `public_ip` **is** applied live by the production module (`public_ip = ""`). `interface_list.labels{}` is covered indirectly but load-bearingly — see the note below. `description_spec` and `node_static_ip.default_gw` are **still open**. |

Totals: 1 n/a, 8 excluded with a reason, 5 partially covered, **155 still open**. Every open row
above is a candidate slice, not a defect — but the table is no longer silent about them.

All 155 open arms are tracked, so closing epic terraform-provider-xcsh#1207 does not drop them:

| Tracking issue | Families | Arms |
|---|---|---|
| mcn #646 | J, L, M, N — `local_vrf` oneofs + the six `SiteStaticRoutesListType` subtrees | 96 |
| mcn #647 | K, O, P, Q — SLI `network_option`, `ipv6_auto_config.router`, `cluster_static_ip`, bond remainder | 33 |
| mcn #648 | B, C, D, E, F, H, I — `advanced_delivery`/`log_anonymization` oneofs, `tunnel_*`, `annotations`/`disable`, `custom_proxy` remainder, ref `tenant` | 26 |

Two details that would not fit in a table cell:

- **Family J's shape.** Each of the six `SiteStaticRoutesListType` instances carries `attrs`,
  `ip_address`, `ip_prefixes`, a `default_gateway{}` marker, and a `node_interface.list[].interface`
  ObjectRef (with `kind`/`name`/`namespace`/`tenant`/`uid`). Because all six are identical, one
  selector on one instance would establish the shape for the whole 84.
- **Family Q's `interface_list.labels{}`.** Nobody declares it, yet S8's read-back shows the server
  materializing it (`interface_list[0].labels: {}`). Suppressing exactly that marker is what xcsh
  #1244's import guards do, so the resource's whole import-clean story rests on an arm with no row.
  It is covered in effect, not by declaration — which is why it is listed here rather than as ✅.

### Also confirmed absent from the provider schema

`interface_list.is_management` and `interface_list.is_primary` appear in the API read-back but have
**no attribute in the provider schema at v3.81.1** (a grep of the 997-arm enumeration finds zero
hits). That matches the S3 note's deferral to api-specs-enriched #1049: it needs spec injection and
a regeneration, so it is a provider gap, not a probe gap.

Likewise `segment_vrf` has **no `segment` ObjectRef attribute at all** — the exclusion recorded in
the S4 notes ("needs a Segment object ref the provider cannot yet inject", specs #1053) is
structurally accurate, not an excuse: there is nowhere to put the reference.

### Caveats this audit will not sign off

Read these before treating the ✅ column as proof.

- **A create path verified only by `terraform import` is NOT verified.** This is not hypothetical.
  S6's `xcsh_registration_approval` passed review on an import of an *already-approved* registration
  plus a 0-change plan; the approve `POST` was never exercised, and it could never have worked —
  the provider discarded the required object-typed `passport`, so every real approve returned
  `500 "Validation approval: Passport is required"` (xcsh #1355, fixed in v3.81.1 and only then
  live-proven on a fresh CE). Applied to this matrix: every `Applied ✅` cell here **was** reached
  by a real `apply` (HTTP 200) — that failure was in a different resource. But the **Import-clean
  column is different**, and the S7 note says so: most cells were flipped to ✅ by *reasoning* that
  xcsh #1244's fix is resource-wide (39 of 39 nested `labels` closures guarded), not by re-running
  an import per arm. Only the base/defaults probe, the `blocked_service` members, the
  `network_type` non-default, the l7 `jumbo_enabled` arm and (in S8) both l3 jumbo arms have a
  per-arm import actually observed.
- **`api-specs-enriched#1108`: the contract-diff gate diffs a release against ITSELF, never N-1 → N,
  so it cannot see upstream removals.** F5 dropped **307 schemas and 74 properties** during a
  16-day window and the gate reported none of it — which is how the `apm*` family removal silently
  broke the provider build (xcsh #1351). So a green Contract-diff gate is **not** evidence that
  upstream is stable, and no completeness claim in this file leans on it. The enumeration above is
  a point-in-time snapshot of v3.81.1: arms can vanish under it without any gate going red. Re-run
  the Method above after every provider bump rather than trusting the counts.
- **Every plan-only arm names its reason** — single-node 400, a missing ref object, or an
  entitlement — and the reasons are recorded per row above and in the S3/S4/S5 notes. Where a
  slice *expected* live and got a 400, the row says "reclassified" rather than being quietly
  restated as excluded (`s2s_..._enabled` and `enable_upgrade_drain` went the other way: expected
  plan-only, accepted live, reclassified up).
- **No arm in this file is entitlement-blocked.** That reason appears in other coverage efforts in
  this org (Bot Defense, WAAP); it does not apply to `xcsh_securemesh_site_v2`.

### S8 live evidence

Registry v3.81.1 (`TF_CLI_CONFIG_FILE` pointing at `provider_installation { direct {} }`, never
`~/.terraformrc` `dev_overrides`), disposable probes only:

- `cov-probe-s8-l3jumbo-01` — `perf_arm=perf_mode_l3_enhanced l3_jumbo_arm=jumbo`: apply (1 added)
  → read-back `{"perf_mode_l3_enhanced":{"jumbo":{}}}` → re-plan "no changes" → `state rm` →
  `import system/cov-probe-s8-l3jumbo-01` → post-import plan "no changes" → destroy.
- `cov-probe-s8-l3nojumbo-01` — same arm at its `no_jumbo` default (regression check on making the
  marker a selector): apply → read-back `{"perf_mode_l3_enhanced":{"no_jumbo":{}}}` → re-plan
  "no changes" → import → post-import plan "no changes" → destroy.
- Both destroyed. The live demo sites `ar-bgp-eastus01/02/03` were read over the API only
  (`GET .../securemesh_site_v2s/<site>`, HTTP 200 each) and were never in any Terraform state.

<!--
Slice roadmap:
- S0: probe workspace + this matrix (done).
- S1: numeric-leaf input validation (.tftest.hcl out-of-range rejection) — DONE (verify.sh; provider v3.75.0).
- S2: string-leaf input validation (mac/CIDR/IP/IPv4/node-type) — DONE (verify.sh; provider v3.75.1).
- S3: interface/addressing oneof arms (interface_choice ethernet/bond/vlan; address_choice dhcp_client/static_ip/no_ipv4_address; ipv6_address_choice; monitoring_choice; s2s_iface_choice) — DONE (verify.sh + live matrix; provider v3.76.0).
- S4: networking/services top-level oneof arms (blocked_services, dns/ntp, enterprise proxy, proxy bypass, url categorization, management network, load_balancing vip_vrrp_mode, s2s slo/sli, forward proxy, network policy, log streaming/receiver, site mesh group, segment_vrf) — DONE (verify.sh + live matrix; provider v3.76.0).
- S5: site-mode oneof arms (offline survivability, performance mode, re_select, software_settings versions, kubernetes_upgrade_drain, admin_user_credentials) — DONE (verify.sh + live matrix; provider v3.76.0). S5a live: perf_mode_l3_enhanced, os/sw versions (create-only), offline enable, enable_upgrade_drain (reclassified). S5b plan-only (400): admin_user_credentials, specific_re.
- S7: labels workaround retired (provider v3.77.5) + blocked_services promoted plan-only -> live once the
  x-f5xc-wire-name contract shipped (provider v3.80.0), including the blocked_service service_choice
  members and the new perf_mode_l7_enhanced jumbo sub-oneof — DONE (verify.sh + live matrix).
- S8: completeness audit against provider v3.81.1 — DONE. Mechanical 997-arm schema enumeration;
  every stale annotation reconciled; perf_mode_l3_enhanced jumbo sub-oneof closed (live, both members);
  drain_max_unavailable_node_count lower bound closed; per-file provider-version claims collapsed onto
  versions.tf + the lock file; the stale "object-ref name capped at 63" blocker retired in all six sites
  (mcn #592) and every root plan test now runs with enable_bgp at its true default. Remaining gaps are
  classified above rather than closed — 155 arms still open, tracked as follow-up slices.
  Closes epic terraform-provider-xcsh#1207.
-->
