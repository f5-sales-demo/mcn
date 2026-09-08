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
BASE_REF=""
FULL_CORPUS=0
SELF_TEST=1

while [ $# -gt 0 ]; do
  case "$1" in
  --root)
    ROOT=$(cd "$2" && pwd)
    FULL_CORPUS=1
    SELF_TEST=0
    shift 2
    ;;
  --base)
    BASE_REF=${2:?--base needs a commit}
    shift 2
    ;;
  --all)
    FULL_CORPUS=1
    shift
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

# English-only development deliberately leaves existing locales stale. Validate
# changed locale files in ordinary contribution runs; --all (or --root without
# --base) retains the complete shape check for an explicitly requested corpus audit.
if [ -n "$BASE_REF" ]; then
  FULL_CORPUS=0
elif [ "$FULL_CORPUS" -eq 0 ]; then
  if git -C "$ROOT" rev-parse --verify --quiet origin/main >/dev/null; then
    BASE_REF=$(git -C "$ROOT" merge-base origin/main HEAD)
  fi
  if [ -z "$BASE_REF" ] || [ "$BASE_REF" = "$(git -C "$ROOT" rev-parse HEAD)" ]; then
    BASE_REF=$(git -C "$ROOT" rev-parse --verify HEAD^)
  fi
fi
if [ "$FULL_CORPUS" -eq 0 ]; then
  git -C "$ROOT" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null
fi

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
UNCHANGED=0

while IFS= read -r enfile; do
  rel="${enfile#"${EN}"/}"
  en_fences=$(count "$enfile" '^[[:space:]]*```')
  en_comp=$(count "$enfile" '<(Aside|Steps|CardGrid|LinkCard|Code|Badge)')
  en_imports=$(count "$enfile" '^import ')
  en_bytes=$(wc -c <"$enfile" | tr -d ' ')

  for loc in $LOCALES; do
    lf="${ROOT}/docs/${loc}/${rel}"
    if [ ! -f "$lf" ]; then
      # English development is intentionally allowed to lead locale output.
      # No locale generation runs during ordinary contribution work.
      # This test validates only locale files explicitly supplied.
      echo "  STALE   ${loc}/${rel}: translated counterpart not generated yet"
      MISSING=$((MISSING + 1))
      continue
    fi
    if [ "$FULL_CORPUS" -eq 0 ]; then
      unchanged=0
      git -C "$ROOT" diff --quiet "$BASE_REF" -- "docs/${loc}/${rel}" || unchanged=$?
      if [ "$unchanged" -eq 0 ]; then
        UNCHANGED=$((UNCHANGED + 1))
        continue
      elif [ "$unchanged" -ne 1 ]; then
        echo "cannot determine locale changes" >&2
        exit 2
      fi
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

echo "checked ${CHECKED} supplied locale files; ${UNCHANGED} unchanged; ${MISSING} missing counterparts allowed"
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: every in-scope translation matches its English source structurally"
else
  echo "FAIL: translations diverge structurally from their English source"
fi
if [ "$SELF_TEST" -eq 1 ]; then
  fixture=$(mktemp -d)
  trap 'rm -rf "$fixture"' EXIT
  mkdir -p "$fixture/docs/en" "$fixture/docs/fr"
  printf '%s\n' '---' 'title: Example' '---' 'Example page.' >"$fixture/docs/en/index.mdx"
  cp "$fixture/docs/en/index.mdx" "$fixture/docs/fr/index.mdx"
  git -C "$fixture" init -q
  git -C "$fixture" add docs
  git -C "$fixture" -c user.name='Example' -c user.email='noreply@example.com' commit -qm baseline
  baseline=$(git -C "$fixture" rev-parse HEAD)
  printf '%s\n' '```text' 'new source block' '```' >>"$fixture/docs/en/index.mdx"
  git -C "$fixture" add docs/en
  git -C "$fixture" -c user.name='Example' -c user.email='noreply@example.com' commit -qm english
  bash "$REPO_ROOT/tests/test-translation-parity.sh" --root "$fixture" --base "$baseline" >/dev/null || {
    echo "FAIL: English-only structure change rejected"
    exit 1
  }
  printf '%s\n' 'Changed locale without the new source block.' >>"$fixture/docs/fr/index.mdx"
  git -C "$fixture" add docs/fr
  if bash "$REPO_ROOT/tests/test-translation-parity.sh" --root "$fixture" --base "$baseline" >/dev/null; then
    echo "FAIL: malformed changed locale accepted"
    exit 1
  fi
  cp "$fixture/docs/en/index.mdx" "$fixture/docs/fr/index.mdx"
  git -C "$fixture" add docs/fr
  git -C "$fixture" -c user.name='Example' -c user.email='noreply@example.com' commit -qm locale
  bash "$REPO_ROOT/tests/test-translation-parity.sh" --root "$fixture" --base "$baseline" >/dev/null || {
    echo "FAIL: structurally complete changed locale rejected"
    exit 1
  }
  printf '%s\n' '```text' 'newer source block' '```' >>"$fixture/docs/en/index.mdx"
  if bash "$REPO_ROOT/tests/test-translation-parity.sh" --root "$fixture" --all >/dev/null; then
    echo "FAIL: full-corpus audit ignored stale locale structure"
    exit 1
  fi
  echo "PASS: English-only, changed-locale, and full-corpus regression cases"
fi
exit "$FAIL"
