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
PATTERNS='mcn-ce-ha-|rmordasiewicz|bankexample|wsp-demo|ce-ha-lab-|ar-ecmp-|ar-bgp-|f5-xc-ce-vm-0[0-9]|10\.0\.[0-9]+\.[0-9]+|10\.250\.0\.10|20\.98\.232\.135|203\.0\.113\.'

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

# A checker that cannot fail is worse than no checker, because it reads as a passing
# gate. Plant one violation of each kind and require both to be caught.
if [ "$SELFTEST" -eq 1 ]; then
  echo "3. the check itself catches a planted violation"
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
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: docs name no deployment value in a command, and date the ones they show"
else
  echo "FAIL: docs carry instruction-literals or undated deployment values"
fi
exit "$FAIL"
