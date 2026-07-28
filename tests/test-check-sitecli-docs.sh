#!/usr/bin/env bash
# Hermetic test for scripts/check-sitecli-docs.sh — the credential-free gate that
# keeps the committed CE command catalog and the documentation in agreement.
#
# Builds throwaway trees under a temporary directory and points the script at each
# with --root, so it never inspects the repository it lives in and needs no network
# and no API token. This is the check that runs in CI, where neither exists.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/check-sitecli-docs.sh"

FAIL=0
WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# new_tree <name> — a minimal, internally consistent tree that must pass.
# Two commands: one ExecUser (captured + documented), one Exec (documented, never captured).
new_tree() {
  local root="${WORK}/$1"
  mkdir -p "${root}/sitecli/captures" \
    "${root}/docs/en/customer-edge/commands/network" \
    "${root}/docs/en/customer-edge/commands/system"

  cat >"${root}/sitecli/catalog.json" <<'JSON'
{
  "build": "crt-20250613-3382",
  "source": { "site": "ar-bgp-eastus01", "node": "f5-xc-ce-vm-01" },
  "commands": {
    "netstat":     { "category": "Network Troubleshooting", "tier": "ExecUser" },
    "ip-link-set": { "category": "Network Troubleshooting", "tier": "Exec", "example": " (<device>||<group>) (up||down)" }
  }
}
JSON

  cat >"${root}/sitecli/capture-manifest.json" <<'JSON'
{
  "defaults": { "site": "ar-bgp-eastus01", "node": "f5-xc-ce-vm-01", "max_lines": 60 },
  "commands": { "netstat": { "args": [] } }
}
JSON

  printf 'Active Internet connections\n' >"${root}/sitecli/captures/sitecli-netstat.txt"
  printf 'sitecli/captures/sitecli-netstat.txt\n' >"${root}/docs/_imports"

  cat >"${root}/docs/en/customer-edge/commands/index.mdx" <<'MDX'
---
title: Command reference
description: Every Site CLI command reachable through the debug API.
---

Captured from software build `crt-20250613-3382`.
MDX

  cat >"${root}/docs/en/customer-edge/commands/network/netstat.mdx" <<'MDX'
---
title: netstat
description: Socket and connection state on the node.
---

## `netstat`

```text file=../../../../_data/sitecli-netstat.txt
```
MDX

  cat >"${root}/docs/en/customer-edge/commands/network/ip.mdx" <<'MDX'
---
title: ip
description: Interface and link state.
---

## `ip-link-set`

Mutating, and in the privileged `Exec` tier. Never run by the capture harness.
MDX

  echo "$root"
}

_run() {
  local rc=0
  bash "$SCRIPT" --root "$1" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

assert_pass() {
  local label="$1" rc
  rc=$(_run "$2")
  if [ "$rc" -eq 0 ]; then echo "[OK] $label -> pass"; else
    echo "[FAIL] $label — expected pass (0), got $rc"
    bash "$SCRIPT" --root "$2" 2>&1 | sed 's/^/       /' | head -8
    FAIL=1
  fi
}

assert_reject() {
  local label="$1" rc
  rc=$(_run "$2")
  if [ "$rc" -eq 1 ]; then echo "[OK] $label -> rejected"; else
    echo "[FAIL] $label — expected rejection (1), got $rc"
    FAIL=1
  fi
}

# --- the consistent baseline ---------------------------------------------------
t=$(new_tree baseline)
assert_pass "internally consistent tree" "$t"

# --- a command on the CE that nobody documented --------------------------------
t=$(new_tree undocumented)
jq '.commands["dig"] = {"category":"Network Troubleshooting","tier":"ExecUser"}' \
  "${t}/sitecli/catalog.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/catalog.json"
jq '.commands["dig"] = {"args":["example.com"]}' \
  "${t}/sitecli/capture-manifest.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/capture-manifest.json"
printf 'x\n' >"${t}/sitecli/captures/sitecli-dig.txt"
printf 'sitecli/captures/sitecli-dig.txt\n' >>"${t}/docs/_imports"
assert_reject "catalog command with no documentation" "$t"

# --- a documented command that is not on the CE --------------------------------
t=$(new_tree invented)
cat >"${t}/docs/en/customer-edge/commands/network/invented.mdx" <<'MDX'
---
title: made up
description: Not a real command.
---

## `totally-not-a-command`
MDX
assert_reject "documented command absent from the catalog" "$t"

# --- an on-box capture is legitimate, and must not be rejected -----------------
# The debug API exposes 34 commands; the appliance's own Site CLI exposes 82, and
# 55 of those have no API equivalent. Captures for them are keyed by exec-catalog.json,
# not catalog.json. Validating only against the API catalog rejected every one.
t=$(new_tree onbox-capture)
cat >"${t}/sitecli/exec-catalog.json" <<'JSON'
{
  "_provenance": {"node": "test", "site_state": "PROVISIONED"},
  "top_level": {"health": "Status of the node"},
  "execcli": {"vegactl-introspect-show-election": "check vegactl cluster primary election status"},
  "counts": {"top_level": 1, "execcli": 1}
}
JSON
printf 'role: Master\n' >"${t}/sitecli/captures/sitecli-vegactl-introspect-show-election.txt"
assert_pass "capture for an on-box-only command in exec-catalog.json" "$t"

# --- a capture in neither catalog is still a violation -------------------------
t=$(new_tree ghost-capture)
cat >"${t}/sitecli/exec-catalog.json" <<'JSON'
{"top_level": {}, "execcli": {"vegactl-introspect-show-election": "x"}, "counts": {}}
JSON
printf 'x\n' >"${t}/sitecli/captures/sitecli-not-a-real-command.txt"
assert_reject "capture matching neither catalog" "$t"

# --- a page may document an on-box-only command ---------------------------------
# 55 of the 82 on-box commands have no debug-API equivalent. Validating documented
# commands against catalog.json alone rejected every page that covers them.
t=$(new_tree onbox-documented)
cat >"${t}/sitecli/exec-catalog.json" <<'JSON'
{
  "top_level": {},
  "execcli": {"vegactl-introspect-show-election": "check vegactl cluster primary election status"},
  "counts": {"top_level": 0, "execcli": 1}
}
JSON
cat >"${t}/docs/en/customer-edge/commands/network/vega.mdx" <<'MDX'
---
title: Vega
description: Control plane introspection.
---

## `vegactl-introspect-show-election`
MDX
assert_pass "page documenting an on-box-only command" "$t"

# --- a page documenting a name in neither catalog is still a violation ----------
t=$(new_tree onbox-ghost-doc)
cat >"${t}/sitecli/exec-catalog.json" <<'JSON'
{"top_level": {}, "execcli": {"vegactl-introspect-show-election": "x"}, "counts": {}}
JSON
cat >"${t}/docs/en/customer-edge/commands/network/ghost.mdx" <<'MDX'
---
title: Ghost
description: Documents something that does not exist.
---

## `vegactl-invented-subcommand`
MDX
assert_reject "page documenting a name in neither catalog" "$t"

# --- captured output for a privileged command is a safety failure --------------
t=$(new_tree exec-captured)
printf 'should never exist\n' >"${t}/sitecli/captures/sitecli-ip-link-set.txt"
printf 'sitecli/captures/sitecli-ip-link-set.txt\n' >>"${t}/docs/_imports"
assert_reject "capture file exists for an Exec-tier command" "$t"

# --- a page embedding output that was never captured ---------------------------
t=$(new_tree dangling-ref)
cat >>"${t}/docs/en/customer-edge/commands/network/netstat.mdx" <<'MDX'

```text file=../../../../_data/sitecli-nowhere.txt
```
MDX
assert_reject "_data reference with no capture file" "$t"

# --- a capture that the build never stages -------------------------------------
t=$(new_tree missing-import)
printf 'Flow table\n' >"${t}/sitecli/captures/sitecli-flow-l.txt"
jq '.commands["flow-l"] = {"category":"Network Troubleshooting","tier":"ExecUser"}' \
  "${t}/sitecli/catalog.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/catalog.json"
jq '.commands["flow-l"] = {"args":[]}' \
  "${t}/sitecli/capture-manifest.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/capture-manifest.json"
cat >"${t}/docs/en/customer-edge/commands/network/flow.mdx" <<'MDX'
---
title: flow
description: Flow table.
---

## `flow-l`

```text file=../../../../_data/sitecli-flow-l.txt
```
MDX
# deliberately NOT added to docs/_imports
assert_reject "referenced capture missing from docs/_imports" "$t"

# --- the build stated in the docs must match the catalog stamp -----------------
t=$(new_tree build-mismatch)
sed -i.bak 's/crt-20250613-3382/crt-20260201-0179/' \
  "${t}/docs/en/customer-edge/commands/index.mdx"
rm -f "${t}/docs/en/customer-edge/commands/index.mdx.bak"
assert_reject "documented build differs from the catalog stamp" "$t"

# --- a manifest entry for a command that no longer exists ----------------------
t=$(new_tree stale-manifest)
jq '.commands["removed-command"] = {"args":[]}' \
  "${t}/sitecli/capture-manifest.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/capture-manifest.json"
assert_reject "manifest entry absent from the catalog" "$t"

# --- a runnable command with no manifest entry ---------------------------------
t=$(new_tree missing-manifest)
jq '.commands["vif"] = {"category":"Network Troubleshooting","tier":"ExecUser"}' \
  "${t}/sitecli/catalog.json" >"${t}/tmp" && mv "${t}/tmp" "${t}/sitecli/catalog.json"
cat >"${t}/docs/en/customer-edge/commands/network/vif.mdx" <<'MDX'
---
title: vif
description: Virtual interfaces.
---

## `vif`
MDX
assert_reject "ExecUser command with no manifest entry" "$t"

# --- malformed catalog ---------------------------------------------------------
t=$(new_tree bad-json)
printf '{ not json\n' >"${t}/sitecli/catalog.json"
assert_reject "unparseable catalog" "$t"

# --- an Exec-tier command needs no manifest entry and no capture ---------------
# Restated explicitly: the baseline already relies on this, and it is the invariant
# most likely to be broken by a careless "every command needs an entry" change.
t=$(new_tree exec-needs-nothing)
assert_pass "Exec-tier command documented with neither manifest entry nor capture" "$t"

# --- and finally: THIS repository ----------------------------------------------
# Everything above builds throwaway trees, which proves the checker behaves but says
# nothing about whether the real catalog, manifest, captures and documentation still
# agree. Without this case CI would merge a command added to the catalog and never
# documented, or a capture whose site was renamed, while the suite reported success on
# synthetic input. CI runs tests/test-*.sh and nothing else, so the real gate lives here.
printf '\n## this repository\n'
if OUT=$(bash "$SCRIPT" 2>&1); then
  printf '[OK] %s\n' "$(printf '%s' "$OUT" | tail -1)"
else
  printf '[FAIL] the real catalog, captures and documentation disagree:\n%s\n' "$OUT"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "check-sitecli-docs tests FAILED"
  exit 1
fi
echo "check-sitecli-docs tests passed"
