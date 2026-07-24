# SMSv2 coverage probe

Azure-free. Creates one `xcsh_securemesh_site_v2` object in the `system` namespace
to exercise schema arms. The object creates/reads/deletes with **no backing Azure
VM** (each an HTTP 200). Never targets the live demo sites
(`ar-bgp-eastus01/02/03`).

## Local runs (dev_overrides — no `terraform init`)

`~/.terraformrc` `dev_overrides` points `f5-sales-demo/xcsh` at the local provider
build. dev_overrides forbids `terraform init` (it errors), so run `plan`/`apply`/
`destroy` directly.

```bash
cd coverage/smsv2
set -a; source /tmp/mcn-xcsh.env; set +a   # live XC creds (env-only, never commit)
terraform apply -auto-approve -var probe_name=cov-probe-s0-01
terraform plan  -var probe_name=cov-probe-s0-01   # expect: No changes (idempotent)
terraform destroy -auto-approve -var probe_name=cov-probe-s0-01
```

Use a **fresh `-var probe_name=` per run** — a stale name collides with the tenant's
existing StatusObject and 500s on create.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `probe_name` | `cov-probe-01` | Throwaway site name (override per run). |
| `mtu` | `1500` | eth0 interface MTU. Validator `AtMost(16384)`. |
| `priority` | `10` | eth0 interface priority. Validator `Between(0, 255)`. |
| `vlan_id` | `100` | vlan_interface VLAN tag. Validator `Between(1, 4095)`. |
| `proxy_port` | `8080` | custom_proxy port. Validator `Between(0, 65535)`. |
| `extended_arms` | `true` | Render the `vlan_interface` interface + top-level `custom_proxy` so the `vlan_id`/`proxy_port` leaves are reachable at plan. Set `false` for a live apply — those two arms 400 on this single-node probe, but the base eth0 interface (carrying `mtu`/`priority`) still applies live. |
| `interface_arm` | `ethernet` | eth0 interface_choice oneof: `ethernet` \| `bond` \| `vlan`. `ethernet` is live; `bond`/`vlan` are plan-only (400 live). |
| `address_arm` | `static_ip` | eth0 address_choice oneof: `dhcp_client` \| `static_ip` \| `no_ipv4_address`. All three live-appliable. |
| `ipv6_arm` | `no_ipv6_address` | eth0 ipv6_address_choice oneof: `no_ipv6_address` \| `ipv6_auto_config` \| `static_ipv6_address`. `no_ipv6_address` is live; the other two are plan-only (400 live). |
| `monitor_arm` | `monitor_disabled` | eth0 monitoring_choice oneof: `monitor` \| `monitor_disabled`. Both live-appliable. |
| `s2s_iface_arm` | `disabled` | eth0 site_to_site_connectivity_interface_choice oneof: `disabled` \| `enabled`. Both live-appliable. |

## S3 interface / addressing oneof arms

Every eth0 interface oneof is modeled as an **enum selector** (`interface_arm`, `address_arm`,
`ipv6_arm`, `monitor_arm`, `s2s_iface_arm`) so exactly one member of each oneof renders and no two
siblings ever coexist (which would trip the provider's `ConflictsWith`). Defaults are the live-safe
base arm, so a bare apply (with `extended_arms=false`) stays idempotent and import-clean.

**Live-appliable** (HTTP 200, idempotent, import-clean modulo the known `labels {}` #1244 drift):
`ethernet_interface`, `dhcp_client`, `static_ip`, `no_ipv4_address`, `no_ipv6_address`, `monitor`,
`monitor_disabled`, `site_to_site_connectivity_interface_disabled`, and
`site_to_site_connectivity_interface_enabled` (s2s `enabled` was expected to need s2s wiring but the
single-node `azure` probe accepts it — verified live).

**Plan-only** — these return `[BAD_REQUEST] Invalid request parameters (status: 400)` on the
single-node `azure` not_managed probe, so their schema is proven at PLAN only (like `vlan_id`/
`proxy_port`): `bond_interface` (`interface_arm=bond`), `vlan_interface` (`interface_arm=vlan`),
`static_ipv6_address` (`ipv6_arm=static_ipv6_address`), `ipv6_auto_config`
(`ipv6_arm=ipv6_auto_config`). Their validated leaves (bond `devices` `SizeBetween(1, 8)`,
static_ipv6 `node_static_ip.ip_address` `CIDRValidator()`) are proven by `verify.sh` reject tests;
`vlan_id` `Between(1, 4095)` is already covered by S1.

Live cycle per live-appliable arm (fresh `probe_name`, `extended_arms=false`):

```bash
cd coverage/smsv2
set -a; source /tmp/mcn-xcsh.env; set +a
terraform apply   -auto-approve -var probe_name=cov-probe-s3-x -var extended_arms=false -var monitor_arm=monitor
terraform plan                  -var probe_name=cov-probe-s3-x -var extended_arms=false -var monitor_arm=monitor  # No changes
terraform state rm xcsh_securemesh_site_v2.probe
terraform import  -var probe_name=cov-probe-s3-x -var extended_arms=false -var monitor_arm=monitor xcsh_securemesh_site_v2.probe system/cov-probe-s3-x
terraform plan                  -var probe_name=cov-probe-s3-x -var extended_arms=false -var monitor_arm=monitor  # 0-change modulo labels {}
terraform destroy -auto-approve -var probe_name=cov-probe-s3-x -var extended_arms=false -var monitor_arm=monitor
```

## S4 networking / services oneof arms

Every top-level networking/services oneof is modeled as an **enum selector** (`services_arm`,
`ha_arm`, `dns_arm`, `ntp_arm`, `proxy_arm`, `proxy_bypass_arm`, `url_cat_arm`, `mgmt_net_arm`,
`s2s_slo_arm`, `s2s_sli_arm`, `forward_proxy_arm`, `network_policy_arm`, `logs_arm`, `vip_vrrp_mode`,
`segment_vrf_arm`) that supersedes the pre-S4 base literal so exactly one member of each oneof
renders. Every default is the base arm, so a bare `terraform plan` (all defaults) is unchanged versus
the pre-S4 base (verified: applied the committed base, swapped in the S4 code, defaults plan =
"No changes").

**Live-appliable (S4a)** — apply→idempotent→import (labels{} #1244 drift only)→destroy on the
single-node `azure` probe: `f5_proxy`, `custom_dns`, `custom_ntp`, `custom_proxy_bypass`,
`no_proxy_bypass`, `enable_url_categorization`, `disable_url_categorization`,
`disable_management_network`, `load_balancing.vip_vrrp_mode` (ENABLE + DISABLE), and
`site_mesh_group_on_slo` all-empty (`no_site_mesh_group{} sm_connection_public_ip{}`).

**Plan-only** — proven at plan via `validation.tftest.hcl` positive asserts (would 400 / needs a ref
live):

- `blocked_services` — apply hits a provider round-trip bug (`Provider produced inconsistent result
  after apply: .blocked_services.blocked_service block count changed from 1 to 0`); the `network_type`
  `OneOf` validator is still reject-proven.
- `enable_ha`, `enable_management_network` — 400 on a single-node probe.
- `active_forward_proxy_policies`, `active_enhanced_firewall_policies`, `log_receiver_with_net`,
  `dc_cluster_group_sli`, `dc_cluster_group_slo`, `site_mesh_group_on_slo` (ref variant) — ObjectRefType
  arms whose referents must pre-exist.
- `segment_vrf` — needs a Segment object ref the provider cannot yet inject (specs #1053).

Logs are driven via `log_receiver_with_net`, never the stale top-level `log_receiver` field
(provider #1256).

Live cycle per S4a arm (fresh `probe_name`, `extended_arms=false`):

```bash
cd coverage/smsv2
set -a; source /tmp/mcn-xcsh.env; set +a
terraform apply   -auto-approve -var probe_name=cov-probe-s4-x -var extended_arms=false -var vip_vrrp_mode=VIP_VRRP_ENABLE
terraform plan                  -var probe_name=cov-probe-s4-x -var extended_arms=false -var vip_vrrp_mode=VIP_VRRP_ENABLE  # No changes
terraform state rm xcsh_securemesh_site_v2.probe
terraform import  -var probe_name=cov-probe-s4-x -var extended_arms=false -var vip_vrrp_mode=VIP_VRRP_ENABLE xcsh_securemesh_site_v2.probe system/cov-probe-s4-x
terraform plan                  -var probe_name=cov-probe-s4-x -var extended_arms=false -var vip_vrrp_mode=VIP_VRRP_ENABLE  # 0-change modulo labels {}
terraform destroy -auto-approve -var probe_name=cov-probe-s4-x -var extended_arms=false -var vip_vrrp_mode=VIP_VRRP_ENABLE
```

## S5 site-mode oneof arms

Every site-mode oneof (performance mode, OS/SW version, offline survivability, RE selection, upgrade
drain, admin credentials) is modeled as an **enum selector** (`perf_arm`, `os_arm`/`os_version`,
`sw_arm`/`sw_version`, `offline_arm`, `re_select_arm`, `upgrade_drain_arm`, `vega_arm`, `admin_creds`)
that supersedes the pre-S5 hardcoded literal, plus gated `upgrade_settings` + `admin_user_credentials`
blocks (both unset in the base). Every default renders the identical base member, so a bare
`terraform plan` (all defaults) is unchanged versus the pre-S5 base (verified: defaults
apply→0-change→import→destroy round-trips with only the `labels {}` #1244 drift).

**Live-appliable (S5a)** — apply→idempotent→import (labels{} #1244 drift only)→destroy on the
single-node `azure` probe: `perf_mode_l3_enhanced{no_jumbo{}}`, `operating_system_version`
(`9.2024.6`), `volterra_software_version` (`crt-20250613-3382`; both version leaves are **create-only**
yet round-trip 0-change), `enable_offline_survivability_mode`, and
`upgrade_settings.kubernetes_upgrade_drain.enable_upgrade_drain` (drain count/timeout + vega
sub-oneof). `enable_upgrade_drain` was expected plan-only (k8s worker drain on a non-k8s node) but the
single-node probe accepts it — reclassified live after verification.

**Plan-only (S5b)** — return `[BAD_REQUEST] Invalid request parameters (status: 400)` live on the
single-node probe, so proven at plan via `validation.tftest.hcl` positive asserts:

- `admin_user_credentials` — needs node local services / a multi-node CE. Its `admin_password`
  SecretType uses `clear_secret_info { url = "string:///<base64>" }` — the only dependency-free
  backend (blindfold/vault/wingman need external providers → 400) — with a base64 of a **dummy
  throwaway placeholder**; NO real secret is committed. `ssh_key` `LengthAtMost(8192)` +
  `secret_encoding_type` `OneOf(EncodingNone, EncodingBase64)` are reject-proven at plan.
- `re_select.specific_re` — `primary_re` must name a real RE geography (a dummy name 400s);
  `primary_re` `LengthBetween(1, 64)` reject-proven at plan.

Live cycle per S5a arm (fresh `probe_name`, `extended_arms=false`):

```bash
cd coverage/smsv2
set -a; source /tmp/mcn-xcsh.env; set +a
terraform apply   -auto-approve -var probe_name=cov-probe-s5-x -var extended_arms=false -var os_arm=operating_system_version -var sw_arm=volterra_software_version
terraform plan                  -var probe_name=cov-probe-s5-x -var extended_arms=false -var os_arm=operating_system_version -var sw_arm=volterra_software_version  # No changes
terraform state rm xcsh_securemesh_site_v2.probe
terraform import  -var probe_name=cov-probe-s5-x -var extended_arms=false -var os_arm=operating_system_version -var sw_arm=volterra_software_version xcsh_securemesh_site_v2.probe system/cov-probe-s5-x
terraform plan                  -var probe_name=cov-probe-s5-x -var extended_arms=false -var os_arm=operating_system_version -var sw_arm=volterra_software_version  # 0-change modulo labels {}
terraform destroy -auto-approve -var probe_name=cov-probe-s5-x -var extended_arms=false -var os_arm=operating_system_version -var sw_arm=volterra_software_version
```

## S1 numeric-validation gate

```bash
cd coverage/smsv2
./verify.sh   # credential-free: mocks the xcsh provider; the real v3.75.0 schema validators fire at plan
```

`verify.sh` proves the SMSv2 numeric validators both accept valid bounds and reject
out-of-range input. It wraps `terraform test` because Terraform's `expect_failures` only
captures user custom conditions, not provider schema validators: `validation.tftest.hcl`
asserts the accept case, and `reject-tests/*.tftest.hcl` (one leaf per file, *designed to
fail*) are driven with `-test-directory=reject-tests` while verify.sh asserts each leaf's
exact validator diagnostic. This is the gate the `coverage-smsv2` CI job runs.

Coverage progress is tracked in `../smsv2-coverage-matrix.md`.
