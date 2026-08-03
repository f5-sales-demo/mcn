#!/usr/bin/env bash
# Keeps the committed Customer Edge command catalog and the documentation in
# agreement. Offline, credential-free, and safe to run in CI.
#
#   bash scripts/check-sitecli-docs.sh [--root DIR]
#
# Exit 0 = consistent, exit 1 = violations found.
#
# Why this exists as a separate gate: the catalog can only be refreshed from a
# live CE, and the F5 corporate Entra tenant does not permit provisioning an Azure
# service principal, so no GitHub runner can hold a credential to do it (see
# scripts/capture-sitecli.sh). The committed catalog is therefore CI's proxy for
# the live tenant. CI proves the documentation agrees with the catalog; a human on
# VPN proves the catalog agrees with reality via `capture-sitecli.sh --check`.
#
# The convention this depends on: every command is documented under a heading of
# the form "## `<command>`" on some page below docs/en/customer-edge/commands/.
# That is what makes the documentation machine-checkable rather than merely
# reviewed by eye.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

while [ $# -gt 0 ]; do
  case "$1" in
  --root)
    ROOT=$(cd "${2:?--root needs a value}" && pwd)
    shift 2
    ;;
  -h | --help)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'error: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

CATALOG="${ROOT}/sitecli/catalog.json"
CLASSIFICATION="${ROOT}/sitecli/command-classification.json"
MANIFEST="${ROOT}/sitecli/capture-manifest.json"
CAPTURE_DIR="${ROOT}/sitecli/captures"
DOCS="${ROOT}/docs/en/customer-edge"
CMD_DOCS="${DOCS}/commands"
IMPORTS="${ROOT}/docs/_imports"

VIOLATIONS=0
violation() {
  printf '  %s\n' "$*" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}
section() { printf '%s\n' "$*" >&2; }

command -v jq >/dev/null 2>&1 || {
  printf 'error: jq is required\n' >&2
  exit 2
}

[ -f "$CATALOG" ] || {
  printf 'error: no catalog at %s\n' "$CATALOG" >&2
  exit 1
}
if ! jq -e '.build and (.commands | type == "object")' "$CATALOG" >/dev/null 2>&1; then
  printf 'error: %s is not a valid catalog (needs .build and .commands)\n' "$CATALOG" >&2
  exit 1
fi
[ -f "$MANIFEST" ] || {
  printf 'error: no manifest at %s\n' "$MANIFEST" >&2
  exit 1
}
if ! jq -e '.commands | type == "object"' "$MANIFEST" >/dev/null 2>&1; then
  printf 'error: %s is not a valid manifest\n' "$MANIFEST" >&2
  exit 1
fi
if ! jq -e '
  (.captured_at | type == "string") and
  (.captured_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  ((.captured_at | fromdateiso8601?) != null)
' "$MANIFEST" >/dev/null 2>&1; then
  violation "capture-manifest.json needs a genuine RFC3339 captured_at timestamp"
fi

BUILD=$(jq -r '.build' "$CATALOG")
ALL_CMDS=$(jq -r '.commands | keys[]' "$CATALOG")

# The appliance's own Site CLI is a second, larger surface: 82 commands on the
# build this fleet runs, most of which the vpm/debug API never exposes. Captures
# for those are keyed by exec-catalog.json. Optional, because a checkout may
# predate the SSH harvest.
#
# There is one catalog per BUILD, because the surface grows between builds: a
# glob rather than a single path, so a page may document a command that exists
# on a build the fleet does not run (issue #710). Every such catalog carries its
# build in `_provenance.build`, and the pages say which build they describe —
# the gate only decides whether a documented name was ever observed somewhere,
# not whether an operator can run it today.
ON_BOX_CMDS=""
for catalog in "${ROOT}"/sitecli/exec-catalog*.json; do
  [ -f "$catalog" ] || continue
  ON_BOX_CMDS=$(
    printf '%s\n%s\n' "$ON_BOX_CMDS" \
      "$(jq -r '((.top_level // {}) + (.execcli // {})) | keys[]' "$catalog")"
  )
done
KNOWN_CMDS=$(printf '%s\n%s\n' "$ALL_CMDS" "$ON_BOX_CMDS" | sed '/^$/d' | sort -u)
# Exec tier is privileged: every member either mutates the node or reads a state
# marker. It is never executed, so it has no manifest entry and no capture.
EXEC_CMDS=$(jq -r '.commands | to_entries[] | select(.value.tier == "Exec") | .key' "$CATALOG")
RUNNABLE_CMDS=$(jq -r '.commands | to_entries[] | select(.value.tier != "Exec") | .key' "$CATALOG")

is_in() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

# --- catalog vs manifest -------------------------------------------------------
section "catalog vs manifest"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  if ! jq -e --arg c "$cmd" '.commands | has($c)' "$MANIFEST" >/dev/null; then
    violation "runnable command '${cmd}' has no entry in capture-manifest.json"
  fi
done <<EOF
$RUNNABLE_CMDS
EOF

while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  if ! is_in "$cmd" "$ALL_CMDS"; then
    violation "manifest entry '${cmd}' is not a command on the CE (stale entry)"
  elif is_in "$cmd" "$EXEC_CMDS"; then
    violation "manifest entry '${cmd}' is Exec tier and must never be executed"
  fi
done < <(jq -r '.commands | keys[]' "$MANIFEST")

# --- classification ------------------------------------------------------------
# command-classification.json decides whether a command gets a page, a one-line
# listing, or is held back as unavailable on this build. Two ways it can lie, and
# a reconciliation that counts "classified" and "excluded" separately sees neither:
# the same command in two tier groups, or a command in BOTH tiers (available) and
# not_on_this_build (unavailable). The second one shipped: dig sat in
# passthrough/networking and in debug_api_only at once.
if [ -f "$CLASSIFICATION" ]; then
  section "command classification"

  TIERED=$(jq -r '
    (.tiers // {}) | to_entries[] | .value | to_entries[]
    | select(.key | startswith("_") | not)
    | (if (.value | type) == "object" then (.value.commands // []) else .value end)[]
  ' "$CLASSIFICATION")

  EXCLUDED=$(jq -r '
    (.not_on_this_build // {}) | to_entries[] | .value
    | select(type == "object") | (.commands // [])[]
  ' "$CLASSIFICATION")

  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    violation "command '${cmd}' is classified in more than one tier group"
  done <<EOF
$(printf '%s\n' "$TIERED" | sed '/^$/d' | sort | uniq -d)
EOF

  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    violation "command '${cmd}' is in tiers (available) and not_on_this_build (unavailable)"
  done <<EOF
$(comm -12 <(printf '%s\n' "$TIERED" | sed '/^$/d' | sort -u) \
    <(printf '%s\n' "$EXCLUDED" | sed '/^$/d' | sort -u))
EOF
fi

# --- captures ------------------------------------------------------------------
section "captured output"
if [ -d "$CAPTURE_DIR" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    base=$(basename "$path")
    cmd=${base#sitecli-}
    cmd=${cmd%.txt}
    cmd=${cmd%.json}
    if ! is_in "$cmd" "$KNOWN_CMDS"; then
      violation "capture '${base}' does not correspond to any command in either catalog"
      continue
    fi
    if is_in "$cmd" "$EXEC_CMDS"; then
      violation "capture '${base}' exists for Exec-tier command '${cmd}' — it must never be executed"
    fi
  done < <(find "$CAPTURE_DIR" -type f -name 'sitecli-*' 2>/dev/null | sort)
fi

# --- documentation -------------------------------------------------------------
# Skipped entirely when the pages do not exist yet, so this gate is usable from
# the first commit of the harness rather than only after the docs land.
if [ ! -d "$CMD_DOCS" ]; then
  section "documentation (not present yet — skipping page checks)"
else
  section "documentation"

  PAGES=$(find "$CMD_DOCS" -type f -name '*.mdx' 2>/dev/null | sort)

  # Every "## `<cmd>`" heading across all pages. Trailing content after the closing
  # backtick is allowed, because a heading legitimately carries a <Badge> marking a
  # command as privileged or mutating — which is exactly the case that must not be
  # made harder to write.
  DOCUMENTED=$(printf '%s\n' "$PAGES" | while IFS= read -r p; do
    [ -n "$p" ] && sed -n 's/^##[[:space:]]*`\([^`]*\)`.*$/\1/p' "$p"
  done | sort -u)

  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    is_in "$cmd" "$DOCUMENTED" ||
      violation "command '${cmd}' is on the CE but no page documents it (expected a '## \`${cmd}\`' heading)"
  done <<EOF
$ALL_CMDS
EOF

  # Documented commands are checked against BOTH catalogs. The debug API surface
  # must be documented (the loop above); the larger on-box surface may be, and
  # 55 of its commands exist nowhere in catalog.json. A name in neither catalog
  # is still a violation — that is the case this rule exists for.
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    is_in "$cmd" "$KNOWN_CMDS" ||
      violation "a page documents '${cmd}', which is not a command in either catalog"
  done <<EOF
$DOCUMENTED
EOF

  # The build the pages claim must be the build the catalog was captured from.
  INDEX="${CMD_DOCS}/index.mdx"
  if [ -f "$INDEX" ]; then
    if ! grep -qF -- "$BUILD" "$INDEX"; then
      violation "commands/index.mdx does not state the catalog build '${BUILD}'"
    fi
    # Deliberately NOT also asserting that no OTHER build is mentioned. The page
    # legitimately names a newer build when listing the commands this tenant does not
    # have yet, and forbidding that would push a genuinely useful comparison out of
    # the documentation in order to satisfy a lint.
  else
    violation "missing ${CMD_DOCS#"${ROOT}/"}/index.mdx"
  fi

  # Captured output is dated evidence, not timeless reference material. Every
  # page that renders a capture must expose the exact date generated by the
  # successful capture run. On-box captures have separate provenance and may be
  # historical, so they need an explicit date but must not be relabelled with
  # the debug-API capture date.
  CAPTURE_DATE=$(jq -r '.captured_at // "" | split("T")[0]' "$MANIFEST")
  CURRENT_CAPTURE_COMMANDS=$(jq -r '
    .commands | to_entries[]
    | select((.value.skip // "") == "")
    | .key
  ' "$MANIFEST")
  while IFS= read -r page; do
    [ -n "$page" ] || continue
    grep -qE 'file=[^[:space:]]*_data/sitecli-' "$page" 2>/dev/null || continue
    needs_current_date=0
    while IFS= read -r ref; do
      command_name=${ref#sitecli-}
      command_name=${command_name%.txt}
      if is_in "$command_name" "$CURRENT_CAPTURE_COMMANDS"; then
        needs_current_date=1
        break
      fi
    done < <(
      grep -ohE 'file=[^[:space:]]*_data/(sitecli-[^[:space:]]+)' "$page" |
        sed -E 's|.*_data/||; s|["}]$||'
    )
    if [ "$needs_current_date" -eq 1 ]; then
      grep -qF "Captured ${CAPTURE_DATE}" "$page" ||
        violation "${page#"${ROOT}/"} renders current captures without 'Captured ${CAPTURE_DATE}'"
    elif ! grep -qE 'Captured [0-9]{4}-[0-9]{2}-[0-9]{2}' "$page"; then
      violation "${page#"${ROOT}/"} renders historical on-box captures without a date"
    fi
  done <<EOF
$PAGES
EOF

  # Every embedded capture must exist and be staged into docs/_data by the build.
  # docs-control's deploy workflow copies each docs/_imports path into docs/_data/,
  # flat, so a reference with no import silently renders an empty block.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    [ -f "${CAPTURE_DIR}/${ref}" ] ||
      violation "a page embeds '_data/${ref}' but sitecli/captures/${ref} does not exist"
    if [ -f "$IMPORTS" ]; then
      grep -qxF "sitecli/captures/${ref}" "$IMPORTS" ||
        violation "'sitecli/captures/${ref}' is embedded by a page but missing from docs/_imports"
    else
      violation "pages embed _data files but there is no docs/_imports"
    fi
  done < <(printf '%s\n' "$PAGES" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    # `|| true` is load-bearing: a page with no embedded capture makes grep exit
    # 1, `pipefail` propagates that through sed, and `set -e` would then kill
    # this subshell mid-scan. index.mdx sorts first and has no reference, so
    # without this the scan silently stopped before reaching any real page.
    grep -ohE 'file=[^[:space:]]*_data/(sitecli-[^[:space:]]+)' "$p" 2>/dev/null |
      sed 's|.*_data/||' || true
  done | sort -u)
fi

printf '\n' >&2
if [ "$VIOLATIONS" -ne 0 ]; then
  printf 'check-sitecli-docs: %s violation(s) — build %s\n' "$VIOLATIONS" "$BUILD" >&2
  exit 1
fi
printf 'check-sitecli-docs: consistent — build %s, %s commands\n' \
  "$BUILD" "$(printf '%s\n' "$ALL_CMDS" | sed '/^$/d' | wc -l | tr -d ' ')" >&2
