#!/usr/bin/env bash
# Checks that each translated page is STRUCTURALLY the same document as its English
# source, which the freshness audit cannot tell.
#
# The managed Translation Audit compares `i18n.sourceHash` against the English file's
# hash. That proves a translation was produced from the current English text. It says
# nothing about whether the result is intact — a file can carry a perfectly correct
# hash and be truncated, or have lost a code fence, or have had its component imports
# mangled. That has happened here twice on separate days, in both cases silently: the
# translator logged success for the run while one file inside it had failed.
#
# So this compares counts that translation must not change:
#
#   * fenced code blocks — a lost fence swallows a command into prose
#   * component usages (<Aside, <Steps, <CardGrid, <LinkCard, <Code, <Badge)
#   * import lines — a page that uses a component and lost its import fails the build
#
# and applies a length floor, because a truncated file is the most common failure and
# is otherwise invisible.
#
# Prose length itself is NOT compared: German and Arabic legitimately run long, CJK
# short. Only structure is required to match.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROOT="$REPO_ROOT"

while [ $# -gt 0 ]; do
  case "$1" in
  --root)
    ROOT=$(cd "$2" && pwd)
    shift 2
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

LOCALES="fr es de pt-br ja ko zh-cn zh-tw ar it hi th"
EN="${ROOT}/docs/en"

if [ ! -d "$EN" ]; then
  echo "no docs/en under ${ROOT}" >&2
  exit 2
fi

# count <file> <pattern> — occurrences of an extended-regex pattern.
count() { grep -cE "$2" "$1" 2>/dev/null || true; }

FAIL=0
CHECKED=0
MISSING=0

while IFS= read -r enfile; do
  rel="${enfile#"${EN}"/}"
  en_fences=$(count "$enfile" '^[[:space:]]*```')
  en_comp=$(count "$enfile" '<(Aside|Steps|CardGrid|LinkCard|Code|Badge)')
  en_imports=$(count "$enfile" '^import ')
  en_bytes=$(wc -c <"$enfile" | tr -d ' ')

  for loc in $LOCALES; do
    lf="${ROOT}/docs/${loc}/${rel}"
    if [ ! -f "$lf" ]; then
      echo "  MISSING ${loc}/${rel}"
      MISSING=$((MISSING + 1))
      FAIL=1
      continue
    fi
    CHECKED=$((CHECKED + 1))

    l_fences=$(count "$lf" '^[[:space:]]*```')
    l_comp=$(count "$lf" '<(Aside|Steps|CardGrid|LinkCard|Code|Badge)')
    l_imports=$(count "$lf" '^import ')
    l_bytes=$(wc -c <"$lf" | tr -d ' ')

    if [ "$en_fences" != "$l_fences" ]; then
      echo "  FENCES  ${loc}/${rel}: english ${en_fences}, translated ${l_fences}"
      FAIL=1
    fi
    if [ "$en_comp" != "$l_comp" ]; then
      echo "  COMPS   ${loc}/${rel}: english ${en_comp}, translated ${l_comp}"
      FAIL=1
    fi
    if [ "$en_imports" != "$l_imports" ]; then
      echo "  IMPORTS ${loc}/${rel}: english ${en_imports}, translated ${l_imports}"
      FAIL=1
    fi
    # 30 % floor: catches truncation without tripping on CJK, which compresses.
    if [ "$en_bytes" -gt 0 ] && [ $((l_bytes * 100 / en_bytes)) -lt 30 ]; then
      echo "  SHORT   ${loc}/${rel}: ${l_bytes} bytes vs english ${en_bytes} (<30%)"
      FAIL=1
    fi
  done
done < <(find "$EN" -name '*.mdx' -type f | sort)

echo "checked ${CHECKED} translated files across 12 locales; ${MISSING} missing"
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: every translation matches its English source structurally"
else
  echo "FAIL: translations diverge structurally from their English source"
fi
exit "$FAIL"
