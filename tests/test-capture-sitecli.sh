#!/usr/bin/env bash
# Hermetic safety test for scripts/capture-sitecli.sh. A newly discovered
# ExecUser command must never execute until the manifest explicitly classifies
# it; command names and appliance descriptions are not safety evidence.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/repo/scripts" "$WORK/repo/sitecli" "$WORK/bin"
command cp -f "$REPO_ROOT/scripts/capture-sitecli.sh" "$WORK/repo/scripts/"
command cp -f "$REPO_ROOT/scripts/sitecli-scrub.sh" "$WORK/repo/scripts/"

cat >"$WORK/repo/sitecli/capture-manifest.json" <<'JSON'
{
  "captured_at": null,
  "defaults": {
    "site": "mcn-example-eastus01",
    "node": "ce01.lab.internal",
    "max_lines": 60,
    "scrub_profile": "strict"
  },
  "commands": {}
}
JSON

cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
count=0
[ ! -f "$CURL_CALL_COUNT" ] || count=$(cat "$CURL_CALL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$CURL_CALL_COUNT"
case "$count" in
1)
  printf '%s\n' '{"output":"{\"new-command\":[\"System\",\"ExecUser\"]}"}'
  ;;
2)
  printf '%s\n' '{"spec":{"volterra_software_version":"crt-test-build"}}'
  ;;
*)
  : >"$EXECUTED_MARKER"
  printf '%s\n' '{"output":"this command must not have executed","return_code":0}'
  ;;
esac
STUB
chmod +x "$WORK/bin/curl"

echo "1. an unclassified runnable command is default-denied"
OUTPUT="$WORK/capture-output"
if PATH="$WORK/bin:$PATH" \
  CURL_CALL_COUNT="$WORK/curl-count" \
  EXECUTED_MARKER="$WORK/executed" \
  XCSH_API_URL="https://example.invalid" \
  XCSH_API_TOKEN="<XC_API_TOKEN>" \
  bash "$WORK/repo/scripts/capture-sitecli.sh" >"$OUTPUT" 2>&1; then
  echo "  FAIL — capture succeeded with an unclassified command"
  exit 1
fi

if ! grep -qF 'absent from capture-manifest.json' "$OUTPUT"; then
  echo "  FAIL — capture failed for the wrong reason"
  sed 's/^/         /' "$OUTPUT"
  exit 1
fi

if [ -e "$WORK/executed" ]; then
  echo "  FAIL — the unclassified command reached the execute endpoint"
  exit 1
fi

if [ "$(cat "$WORK/curl-count")" -ne 2 ]; then
  echo "  FAIL — expected discovery and build calls only"
  exit 1
fi

echo "  ok   — stopped before executing the unclassified command"
echo "PASS: Site CLI capture safety"
