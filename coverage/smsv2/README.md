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

Live cycle per applyable arm (fresh `probe_name`, `extended_arms=false`):

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
