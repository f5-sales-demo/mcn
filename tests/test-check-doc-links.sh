#!/usr/bin/env bash
# Hermetic test for scripts/check_doc_links.py — the guard behind issue #828.
#
# The bug it exists to catch is not a typo, it is a wrong mental model: relative
# links here resolve against the PAGE URL, so './x/' is correct on an index page
# and wrong on a non-index page, where the same text silently means one directory
# deeper. Both spellings look reasonable in a diff, which is how three of them
# reached published documentation.
#
# So the cases below pin the distinction in both directions: an index page must
# accept './x/' and a non-index page must reject it. A guard that only checked
# one direction would either miss the bug or flag every correct link.
#
# Each case builds its own throwaway docs/ tree and runs the checker inside it,
# so nothing here reads this repository's own documentation.
#
# No network, no credentials, no build.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/check_doc_links.py"

FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# expect <description> <expected-exit> <expected-substring-or-empty>
# Reads the page tree from stdin, one "path<TAB>content" record per line.
expect() {
  local desc="$1" want_exit="$2" want_text="$3"
  local dir out got_exit
  dir=$(mktemp -d "${WORK}/case.XXXXXX")

  while IFS=$'\t' read -r path content; do
    [ -n "$path" ] || continue
    mkdir -p "${dir}/$(dirname "$path")"
    # %b, not %s: a case needs real newlines to build a fenced block, and printf
    # does not expand escapes inside a %s argument.
    printf '%b\n' "$content" >"${dir}/${path}"
  done

  got_exit=0
  out=$(cd "$dir" && python3 "$SCRIPT" 2>&1) || got_exit=$?

  if [ "$got_exit" != "$want_exit" ]; then
    printf 'FAIL %s\n       want exit: %s\n       got exit:  %s\n       output: %s\n' \
      "$desc" "$want_exit" "$got_exit" "$out"
    FAIL=1
    return
  fi

  if [ -n "$want_text" ] && ! printf '%s' "$out" | grep -qF "$want_text"; then
    printf 'FAIL %s\n       want output containing: %s\n       got: %s\n' \
      "$desc" "$want_text" "$out"
    FAIL=1
    return
  fi

  printf 'ok   %s\n' "$desc"
}

# --- The distinction the guard exists to enforce ------------------------------

expect 'index page may use ./ to reach a child' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	See [child](./child/).
docs/en/guide/child.mdx	Child.
CASES

expect 'non-index page using ./ to reach a sibling is a finding' 1 'is not a page' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	Guide.
docs/en/guide/page.mdx	See [sibling](./sibling/).
docs/en/guide/sibling.mdx	Sibling.
CASES

expect 'non-index page using ../ to reach a sibling resolves' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	Guide.
docs/en/guide/page.mdx	See [sibling](../sibling/).
docs/en/guide/sibling.mdx	Sibling.
CASES

expect 'non-index page reaching its own directory index with ../' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	Guide.
docs/en/guide/page.mdx	Back to [the guide](../).
CASES

# --- The exact production regression from issue #828 --------------------------

expect 'the lifecycle.mdx defect is caught' 1 'lifecycle.mdx' <<'CASES'
docs/en/index.mdx	Root.
docs/en/customer-edge/index.mdx	CE.
docs/en/customer-edge/lifecycle.mdx	Read [SSH](./access/ssh/) first.
docs/en/customer-edge/access/index.mdx	Access.
docs/en/customer-edge/access/ssh.mdx	SSH.
CASES

expect 'the lifecycle.mdx fix passes' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/customer-edge/index.mdx	CE.
docs/en/customer-edge/lifecycle.mdx	Read [SSH](../access/ssh/) first.
docs/en/customer-edge/access/index.mdx	Access.
docs/en/customer-edge/access/ssh.mdx	SSH.
CASES

# --- Out of scope: things that do not depend on the page URL ------------------

expect 'external, absolute, mailto and fragment links are ignored' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/page.mdx	[a](https://example.com/x/) [b](/en/absolute/) [c](mailto:dana@example.com) [d](#section)
CASES

expect 'a link inside a fenced block is an example, not a link' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/page.mdx	Example:\n\n```markdown\n[broken](./nowhere/)\n```
CASES

expect 'a component href is checked like a markdown link' 1 'is not a page' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	<LinkCard title="x" href="./missing/" />
CASES

expect 'a query string or fragment does not mask a resolvable page' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	See [child](./child/#section).
docs/en/guide/child.mdx	Child.
CASES

# --- Locale trees are generated, so they are not the authored surface ---------

expect 'a broken link in a locale tree is not reported' 0 '' <<'CASES'
docs/en/index.mdx	Root.
docs/en/guide/index.mdx	Guide.
docs/fr/index.mdx	Racine.
docs/fr/guide/index.mdx	Voir [enfant](./nowhere/).
CASES

# --- Failure to run is distinct from a finding --------------------------------

expect 'no docs directory exits 2, not 1' 2 'run from the repository root' <<'CASES'
README.md	Not documentation.
CASES

expect 'a docs tree with no English pages exits 2' 2 'no pages found' <<'CASES'
docs/fr/index.mdx	Racine.
CASES

if [ "$FAIL" -ne 0 ]; then
  printf '\nFAILED\n'
  exit 1
fi

printf '\nAll check-doc-links cases passed\n'
