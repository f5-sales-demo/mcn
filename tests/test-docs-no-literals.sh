#!/usr/bin/env bash
# Keeps deployment-specific values out of the documentation's PROSE and COMMANDS,
# while still allowing them in captured output.
#
# The distinction is the whole point, so it is worth stating:
#
#   * A literal in a command or in prose is an INSTRUCTION. A reader copies it, and
#     it is wrong for every deployment but one — silently, because a resource group
#     that does not exist looks the same as a command you mistyped. Every such value
#     has a `terraform output` behind it and must be read from there.
#
#   * A literal inside a captured-output fence (```text, ```json, ```console) is
#     EVIDENCE. It is what the command printed on a stated date, and removing it
#     would leave the docs asserting behaviour with nothing to show for it. Those
#     are allowed, and are expected to carry an "Observed <date>" line nearby.
#
# So there are two rules, and neither polices prose style:
#
#   1. No deployment-specific literal inside a bash/sh fence. That is what a reader
#      copies, so it is the one place a literal is unambiguously wrong.
#   2. Any page containing such a literal at all must carry an "Observed YYYY-MM-DD"
#      or "Captured YYYY-MM-DD" marker. Evidence is allowed; UNDATED evidence is not,
#      because a reader cannot tell whether a value was true today or a rebuild ago.
#      The date is required explicitly: the word alone would let "Observed behaviour"
#      satisfy a check that exists to pin evidence to a point in time.
#
# Prose that discusses a value visible in captured output ("the VIP 10.250.0.10/32
# has a single path") is analysis, not an instruction, and is left alone.
#
#   bash tests/test-docs-no-literals.sh            # check docs/en
#   bash tests/test-docs-no-literals.sh --root DIR # check somewhere else (tests)
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROOT="$REPO_ROOT"
SELFTEST=1

while [ $# -gt 0 ]; do
  case "$1" in
  --root)
    ROOT=$(cd "$2" && pwd)
    SELFTEST=0
    shift 2
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

# Values that name THIS deployment rather than any deployment. Each one has an
# output behind it: resource_group_name, route_server_name, bastion_name,
# client_vm_name, xc_site_names, ce_vm_names, lb_domain, origin_ip, vip,
# ce_sli_private_ips, ce_mgmt_private_ips.
#
# The CURRENT names come first, and they matter most. A denylist of names the
# deployment used to have decays into uselessness the moment it is renamed: it keeps
# passing while every command in the docs hardcodes the new name instead. `mcn-ce-ha-`
# is the derived prefix (var.component), so it covers the sites, load balancer, origin
# pool, Route Server, Bastion and test client in one pattern.
#
# The retired names are kept so a stale value cannot come back unnoticed — a copied
# snippet or a reverted edit reintroducing `wsp-demo-pool` should fail here.
#
# 203.0.113. is deliberately NOT here. STYLE_GUIDE.md §"Assign ranges by role"
# tells authors to use TEST-NET-3 for published service addresses, so rejecting it
# would have the gate and the guide contradict each other.
PATTERNS='mcn-ce-ha-|rmordasiewicz|bankexample|wsp-demo|ce-ha-lab-|ar-ecmp-|ar-bgp-|f5-xc-ce-vm-0[0-9]|10\.0\.[0-9]+\.[0-9]+|10\.250\.0\.10|20\.98\.232\.135'

# Identity, not deployment values — and the instruction/evidence distinction does
# not apply to it. A deployment value inside an output fence is evidence: it shows
# what the system did, and nobody copies it. An account name or a tenant identifier
# inside an output fence is still an account name and a tenant identifier, published
# in a public repository. STYLE_GUIDE §"Personally identifiable information" lists
# user names and party-specific identifiers with no fence-type exemption.
#
# This is how `rg-mcn-ce-ha-rmordasiewicz` reached a `text` fence in
# docs/en/customer-edge/access/site-console.mdx and passed every gate.
#
# The tenant is matched by its console host rather than by name: the bare string
# `f5-sales-demo` is also the npm scope and the GitHub organisation, both of which
# are legitimate in prose and imports.
IDENTITY_PATTERNS='rmordasiewicz|[a-z0-9-]+\.console\.ves\.volterra\.io'

scan() {
  # Emits "path:line:text" for every offending line: a match that is NOT inside a
  # captured-output fence. Fence language decides: bash/sh/shell are instructions,
  # everything else (text, json, console, hcl, yaml) is output or configuration.
  local dir="$1"
  find "$dir" -name '*.mdx' -type f | sort | while IFS= read -r f; do
    awk -v pat="$PATTERNS" -v file="$f" '
      /^[[:space:]]*```/ {
        if (infence) { infence = 0; lang = "" }
        else {
          infence = 1
          line = $0
          sub(/^[[:space:]]*```/, "", line)
          split(line, parts, /[[:space:]]/)
          lang = parts[1]
        }
        next
      }
      {
        # Only commands are instructions. Prose and output fences are not.
        if (!infence) next
        if (lang != "bash" && lang != "sh" && lang != "shell") next
        if ($0 ~ pat) printf "%s:%d:%s\n", file, NR, $0
      }
    ' "$f"
  done
}

scan_identity() {
  # Emits "path:line:text" for every identity match, wherever it appears. No fence
  # logic on purpose: there is no context in a published page that makes an account
  # name or a customer's tenant acceptable.
  local dir="$1"
  find "$dir" -name '*.mdx' -type f | sort | while IFS= read -r f; do
    grep -nE "$IDENTITY_PATTERNS" "$f" | sed "s|^|${f}:|"
  done
}

FAIL=0

echo "1. no deployment-specific literal inside a command"
OFFENDERS=$(scan "${ROOT}/docs/en" || true)
if [ -z "$OFFENDERS" ]; then
  echo "  ok   — no command carries a deployment-specific literal"
else
  echo "  FAIL — these are instructions a reader would copy; read them from an output instead:"
  printf '%s\n' "$OFFENDERS" | sed 's/^/         /'
  FAIL=1
fi

echo "2. every page carrying such a literal dates it"
UNDATED=""
while IFS= read -r f; do
  if grep -qE "$PATTERNS" "$f" && ! grep -qE "(Observed|Captured) [0-9]{4}-[0-9]{2}-[0-9]{2}" "$f"; then
    UNDATED="${UNDATED}${f}"$'\n'
  fi
done < <(find "${ROOT}/docs/en" -name '*.mdx' -type f | sort)
if [ -z "$UNDATED" ]; then
  echo "  ok   — every page showing a deployment value says when it was observed"
else
  echo "  FAIL — these show deployment-specific values with no \"Observed YYYY-MM-DD\" marker:"
  printf '%s' "$UNDATED" | sed '/^$/d;s/^/         /'
  FAIL=1
fi

# Scanned across every locale, not just docs/en. Rules 1 and 2 are about what a
# reader copies and are checked on the English source the translations derive from.
# Identity is different: a machine translation copies an account name through
# verbatim, so a single leak in English becomes thirteen published copies.
echo "3. no account name or tenant identifier anywhere on a page, in any locale"
IDENTITY_HITS=$(scan_identity "${ROOT}/docs" || true)
if [ -z "$IDENTITY_HITS" ]; then
  echo "  ok   — no page names a person or a tenant"
else
  echo "  FAIL — these identify a person or a customer; use a placeholder or an output:"
  printf '%s\n' "$IDENTITY_HITS" | sed 's/^/         /'
  FAIL=1
fi

# A checker that cannot fail is worse than no checker, because it reads as a passing
# gate. Plant one violation of each kind and require both to be caught.
if [ "$SELFTEST" -eq 1 ]; then
  echo "4. the check itself catches a planted violation"
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "${WORK}/docs/en"

  printf '%s\n' \
    '---' 'title: t' '---' '' '```bash' 'ssh admin@10.0.3.7' '```' \
    >"${WORK}/docs/en/prose.mdx"
  printf '%s\n' \
    '---' 'title: t' '---' '' '```bash' 'az group show -g rg-mcn-ce-ha-rmordasiewicz' '```' \
    >"${WORK}/docs/en/command.mdx"
  printf '%s\n' \
    '---' 'title: t' '---' '' 'Observed 2026-07-28:' '' '```text' 'site ar-bgp-eastus01 -> ONLINE' '```' \
    >"${WORK}/docs/en/output.mdx"
  # A person's account name is PII wherever it appears. The output/instruction
  # distinction is right for deployment values and wrong for identity: a reader
  # is not going to copy this, but it is still published either way. This is the
  # exact shape that reached docs/en/customer-edge/access/site-console.mdx:104.
  printf '%s\n' \
    '---' 'title: t' '---' '' 'Observed 2026-07-28:' '' '```text' 'rg-mcn-ce-ha-rmordasiewicz' '```' \
    >"${WORK}/docs/en/identity-in-output.mdx"
  # The tenant's own console host names the customer. STYLE_GUIDE requires a
  # placeholder for a tenant identifier.
  printf '%s\n' \
    '---' 'title: t' '---' '' 'Observed 2026-07-28:' '' '```text' 'https://example-corp.console.ves.volterra.io' '```' \
    >"${WORK}/docs/en/tenant-in-output.mdx"
  # TEST-NET-3 is what STYLE_GUIDE tells authors to use for a published service
  # address, so the gate must not reject it.
  printf '%s\n' \
    '---' 'title: t' '---' '' '```bash' 'curl http://203.0.113.10/' '```' \
    >"${WORK}/docs/en/reserved.mdx"

  PLANTED=$(scan "${WORK}/docs/en" || true)
  if printf '%s' "$PLANTED" | grep -q 'prose.mdx'; then
    echo "  ok   — caught a literal in an ssh command"
  else
    echo "  FAIL — missed a literal in an ssh command"
    FAIL=1
  fi
  if printf '%s' "$PLANTED" | grep -q 'command.mdx'; then
    echo "  ok   — caught a literal in a bash fence"
  else
    echo "  FAIL — missed a literal in a bash fence"
    FAIL=1
  fi
  if printf '%s' "$PLANTED" | grep -q 'output.mdx'; then
    echo "  FAIL — flagged captured output, which is evidence and must be allowed"
    FAIL=1
  else
    echo "  ok   — left captured output alone"
  fi
  if printf '%s' "$PLANTED" | grep -q 'reserved.mdx'; then
    echo "  FAIL — rejected a reserved documentation address; STYLE_GUIDE requires TEST-NET-3 here"
    FAIL=1
  else
    echo "  ok   — allowed a reserved documentation address in a command"
  fi

  IDENTITY=$(scan_identity "${WORK}/docs/en" || true)
  if printf '%s' "$IDENTITY" | grep -q 'identity-in-output.mdx'; then
    echo "  ok   — caught an account name inside captured output"
  else
    echo "  FAIL — missed an account name inside captured output; PII is not evidence"
    FAIL=1
  fi
  if printf '%s' "$IDENTITY" | grep -q 'tenant-in-output.mdx'; then
    echo "  ok   — caught a tenant console host inside captured output"
  else
    echo "  FAIL — missed a tenant console host; a tenant identifier names a customer"
    FAIL=1
  fi
  if printf '%s' "$IDENTITY" | grep -q '/output\.mdx:'; then
    echo "  FAIL — identity scan flagged an ordinary deployment value"
    FAIL=1
  else
    echo "  ok   — identity scan left ordinary deployment values to rule 1"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: docs name no deployment value in a command, and date the ones they show"
else
  echo "FAIL: docs carry instruction-literals or undated deployment values"
fi
exit "$FAIL"
