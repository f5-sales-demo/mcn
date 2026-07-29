#!/usr/bin/env bash
# A double-quoted JSX attribute cannot contain a straight double quote. MDX stops
# parsing the attribute at the second `"`, treats what follows as another attribute
# name, and fails the build:
#
#   <Aside type="caution" title="提示"无此设备或地址"的 panic 意味着认证已成功">
#                                    ^ attribute ends here
#
#   Unexpected character `"` (U+0022) in attribute name ...
#
# This broke the Pages deploy on main after PR #711 merged (issue #712). Nothing
# else in the pipeline catches it:
#
#   * translation parity compares fence and component COUNTS, which still matched;
#   * the i18n.sourceHash audit proves freshness, not that the file parses;
#   * docs-translate reported success for the file;
#   * CI's MARKDOWN and NATURAL_LANGUAGE linters both passed.
#
# The English pages avoid this by using single quotes inside an attribute, but a
# translator will not necessarily preserve that, so the risk is highest in the
# twelve generated locales — which is exactly where a human is least likely to look.
#
# MDX aborts on the FIRST parse error, so one bad attribute hides every one behind
# it. This scans all files and reports all of them.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONTENT="${ROOT}/docs"

VIOLATIONS=0

# A double-quoted attribute value that itself contains a double quote. Anchored on
# `attr="` so prose containing quotes is untouched — only attribute values match.
PATTERN='<[A-Z][A-Za-z]*[^>]*[a-zA-Z-]+="[^"]*"[^=">]*"'

scan() {
  local dir="$1" label="$2" found=0
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    printf '  [FAIL] %s\n' "$hit"
    found=$((found + 1))
  done < <(grep -rnoE "$PATTERN" "$dir" --include='*.mdx' 2>/dev/null || true)
  if [ "$found" -gt 0 ]; then
    printf '%s: %d nested-quote attribute(s)\n' "$label" "$found" >&2
    VIOLATIONS=$((VIOLATIONS + found))
  else
    printf '  ok   — %s\n' "$label"
  fi
}

printf '1. no .mdx nests a straight quote inside a JSX attribute\n'
scan "$CONTENT" "every locale under docs/"

# --- the check must be able to fail -------------------------------------------
#
# A scan that reports nothing is worthless if it cannot report anything. Plant a
# violation in a temporary tree and require the pattern to catch it, and a safe
# variant to pass, so a regex that silently stops matching fails this script
# instead of blessing the repository.
printf '2. the check itself catches a planted violation\n'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"${TMP}/bad.mdx" <<'BAD'
<Aside type="caution" title="a phrase "quoted" inside the attribute">
body
</Aside>
BAD

cat >"${TMP}/good.mdx" <<'GOOD'
<Aside type="caution" title="a phrase 'quoted' with single quotes">
body
</Aside>

Prose may contain "double quotes" freely, and <Aside type="note" title="plain"> is fine.
GOOD

if grep -rqE "$PATTERN" "${TMP}/bad.mdx"; then
  printf '  ok   — caught the planted nested quote\n'
else
  printf '  [FAIL] the pattern did not catch a known-bad attribute\n' >&2
  VIOLATIONS=$((VIOLATIONS + 1))
fi

if grep -rqE "$PATTERN" "${TMP}/good.mdx"; then
  printf '  [FAIL] the pattern flagged a file that is legitimate\n' >&2
  grep -rnoE "$PATTERN" "${TMP}/good.mdx" >&2 || true
  VIOLATIONS=$((VIOLATIONS + 1))
else
  printf '  ok   — left single quotes and prose quotes alone\n'
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  printf 'FAIL: %d problem(s). A double-quoted JSX attribute must not contain a double quote — use single quotes inside it.\n' "$VIOLATIONS" >&2
  exit 1
fi

printf 'PASS: every JSX attribute in every locale parses as MDX\n'
