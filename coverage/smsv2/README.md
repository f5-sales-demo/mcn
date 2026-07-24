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
| `mtu` | `1500` | SLO interface MTU (0 or 512-16384). |
| `vlan_id` | `100` | vlan_interface id (1-4095) — wired for S3. |
| `priority` | `10` | Interface priority (0-255) — wired for S1/S3. |
| `proxy_port` | `8080` | custom_proxy port (0-65535) — wired for S3. |

Coverage progress is tracked in `../smsv2-coverage-matrix.md`.
