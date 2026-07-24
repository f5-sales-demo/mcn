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
