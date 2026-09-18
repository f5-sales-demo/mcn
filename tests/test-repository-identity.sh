#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

old_identity='https://github.com/f5-sales-demo/mcn|https://f5-sales-demo\.github\.io/mcn|/mcn/images/'
if findings=$(rg -n "$old_identity" docs); then
  printf 'live old repository identity remains in documentation:\n%s\n' "$findings" >&2
  exit 1
fi

jq -e '
  all(.[].url;
    startswith("https://f5-sales-demo.github.io/multi-cloud-networking/")
  )
' docs/llms-links.json >/dev/null

printf 'repository identity checks passed\n'
