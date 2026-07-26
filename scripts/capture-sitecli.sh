#!/usr/bin/env bash
# Captures the Customer Edge Site CLI command surface, and the output of the
# read-only commands, from a live CE via the F5 XC vpm debug API.
#
#   bash scripts/capture-sitecli.sh                 # discover + capture
#   bash scripts/capture-sitecli.sh --discover-only  # refresh the catalog only
#   bash scripts/capture-sitecli.sh --check          # drift gate, writes nothing
#
# This is a WORKSTATION script. The F5 corporate Entra tenant does not permit
# provisioning an Azure service principal, so there is no credential a GitHub
# runner could hold; CI verifies the committed catalog against the documentation
# instead (scripts/check-sitecli-docs.sh). Do not wire this into CI.
#
# ---------------------------------------------------------------------------
# Three routing rules, all established by probing the live API rather than from
# any published document. The catalog itself tells you which rule applies:
#
#   entry = [category, tier, exampleArg?, scope?]
#
#   1. scope == "GLOBAL"   -> GET  .../vpm/debug/global/<cmd>
#      Returns structured JSON, NOT text, and is NOT reachable through exec-user
#      (which answers "command not supported"). Only `health` and `diagnosis`.
#   2. tier  == "ExecUser" -> POST .../vpm/debug/<node>/exec-user
#      Body {"namespace","site","node","command":[<argv>]}. Returns {output, return_code}.
#   3. tier  == "Exec"     -> POST .../vpm/debug/<node>/exec
#      Privileged, and every member of this tier either mutates the node or is a
#      state marker. NEVER CALLED by this script. Documented from metadata only.
#
# Discovery is by OMISSION: POST with no "command" key returns the catalog. An
# unknown command value returns an error, not the catalog.
# ---------------------------------------------------------------------------
#
# Captured output is a dated evidence snapshot, not a reproducible artifact:
# container ages, packet counters and uptimes move between runs, so re-capturing
# legitimately produces a diff. The CATALOG is the stable contract, and --check
# compares only the catalog and the software build.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRUB="${REPO_ROOT}/scripts/sitecli-scrub.sh"
OUT_DIR="${REPO_ROOT}/sitecli"
CATALOG="${OUT_DIR}/catalog.json"
MANIFEST="${OUT_DIR}/capture-manifest.json"
CAPTURE_DIR="${OUT_DIR}/captures"

CONTEXT="${XCSH_CONTEXT:-f5-sales-demo}"
NAMESPACE="system"
SITE=""
NODE=""
MODE="capture"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
note() { printf '%s\n' "$*" >&2; }

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
  --context)
    CONTEXT="${2:?--context needs a value}"
    shift 2
    ;;
  --site)
    SITE="${2:?--site needs a value}"
    shift 2
    ;;
  --node)
    NODE="${2:?--node needs a value}"
    shift 2
    ;;
  --namespace)
    NAMESPACE="example-corp"
    shift 2
    ;;
  --check)
    MODE="check"
    shift
    ;;
  --discover-only)
    MODE="discover"
    shift
    ;;
  -h | --help) usage ;;
  --token | --api-token)
    die "refusing a token on the command line: it lands in shell history and
       process listings. Set XCSH_API_TOKEN, or use the xcsh context file."
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "$SCRUB" ] || die "missing $SCRUB"

# --- credentials -------------------------------------------------------------
# Environment wins; otherwise read the xcsh context file. Never a CLI argument.
API_URL="${XCSH_API_URL:-}"
API_TOKEN="${XCSH_API_TOKEN:-}"
if [ -z "$API_URL" ] || [ -z "$API_TOKEN" ]; then
  CTX_FILE="${HOME}/.config/xcsh/contexts/${CONTEXT}.json"
  [ -f "$CTX_FILE" ] || die "no XCSH_API_URL/XCSH_API_TOKEN in the environment and no context at $CTX_FILE"
  [ -n "$API_URL" ] || API_URL=$(jq -r '.apiUrl // empty' "$CTX_FILE")
  [ -n "$API_TOKEN" ] || API_TOKEN=$(jq -r '.apiToken // empty' "$CTX_FILE")
fi
[ -n "$API_URL" ] || die "could not resolve the API URL"
[ -n "$API_TOKEN" ] || die "could not resolve the API token"

# The tenant name, taken from the API host, is handed to the scrub filter. It shows
# up inside the internal SA names that ipsec-status and health print — carrying a
# unique suffix — which the console-hostname rule alone never caught. Derived rather
# than hardcoded so this works against any tenant.
SITECLI_TENANT=$(printf '%s' "$API_URL" | sed -E 's#^https?://##; s#/.*##; s#\..*##')
export SITECLI_TENANT

# --- manifest defaults -------------------------------------------------------
if [ -f "$MANIFEST" ]; then
  [ -n "$SITE" ] || SITE=$(jq -r '.defaults.site // empty' "$MANIFEST")
  [ -n "$NODE" ] || NODE=$(jq -r '.defaults.node // empty' "$MANIFEST")
fi
[ -n "$SITE" ] || SITE="ar-bgp-eastus01"
[ -n "$NODE" ] || NODE="f5-xc-ce-vm-01"

SITE_BASE="${API_URL}/api/operate/namespaces/${NAMESPACE}/sites/${SITE}"

# Handed to the scrub filter so it can remove hostnames that no address rule would
# see — a netstat host:port column, a journal line prefix.
SITECLI_NODE="$NODE"
SITECLI_SITE="$SITE"
export SITECLI_NODE SITECLI_SITE

# The redaction profile is declared by the manifest, not defaulted here, so the
# choice is visible in a diff and has to be reviewed. Absent a declaration the
# filter defaults to strict, which is the safe direction: for a company customer,
# internal addressing, MAC addresses and AS numbers ARE identifying information.
if [ -z "${SITECLI_SCRUB_PROFILE:-}" ] && [ -f "$MANIFEST" ]; then
  SITECLI_SCRUB_PROFILE=$(jq -r '.defaults.scrub_profile // empty' "$MANIFEST")
fi
export SITECLI_SCRUB_PROFILE="${SITECLI_SCRUB_PROFILE:-strict}"
case "$SITECLI_SCRUB_PROFILE" in
strict) ;;
lab)
  note "scrub profile: lab — internal addressing, MAC addresses and AS numbers are"
  note "                     PRESERVED. Correct only for F5-owned demo infrastructure."
  ;;
*) die "unknown scrub profile: ${SITECLI_SCRUB_PROFILE} (expected strict or lab)" ;;
esac

# curl with the token supplied on stdin, so it never appears in the process list.
api() {
  local method="$1" url="$2" body="${3:-}"
  local -a args=(-sS --max-time 120 -X "$method" -H @- -H "Content-Type: application/json")
  [ -n "$body" ] && args+=(--data "$body")
  printf 'Authorization: APIToken %s\n' "$API_TOKEN" | curl "${args[@]}" "$url"
}

# --- software build ----------------------------------------------------------
fetch_build() {
  api GET "${API_URL}/api/config/namespaces/${NAMESPACE}/sites/${SITE}" |
    jq -r '.spec.volterra_software_version // .get_spec.volterra_software_version // empty'
}

# --- discovery: POST exec-user with no "command" key -------------------------
fetch_catalog_raw() {
  api POST "${SITE_BASE}/vpm/debug/${NODE}/exec-user" \
    "$(jq -nc --arg ns "$NAMESPACE" --arg s "$SITE" --arg n "$NODE" \
      '{namespace:$ns, site:$s, node:$n}')" |
    jq -r '.output // empty'
}

# Normalise the raw catalog into a stable, reviewable shape. No timestamps: the
# catalog must be byte-identical across runs when the CE has not changed.
build_catalog_json() {
  local raw="$1" build="$2"
  printf '%s' "$raw" | jq -S \
    --arg build "$build" --arg site "$SITE" --arg node "$NODE" \
    '{
       build: $build,
       source: { site: $site, node: $node },
       commands: with_entries(
         .value |= {
           category: .[0],
           tier:     .[1]
         }
         + (if (length > 2 and .[2] != "") then { example: .[2] } else {} end)
         + (if (length > 3 and .[3] != "") then { scope:   .[3] } else {} end)
       )
     }'
}

RAW=$(fetch_catalog_raw)
[ -n "$RAW" ] || die "discovery returned nothing — check the site/node names and the token"
printf '%s' "$RAW" | jq -e 'type == "object"' >/dev/null 2>&1 ||
  die "discovery did not return a catalog object; got: $(printf '%s' "$RAW" | head -c 200)"

BUILD=$(fetch_build)
[ -n "$BUILD" ] || die "could not read volterra_software_version for site $SITE"
NEW_CATALOG=$(build_catalog_json "$RAW" "$BUILD")

# --- check mode: compare the contract, not the evidence ----------------------
if [ "$MODE" = "check" ]; then
  [ -f "$CATALOG" ] || die "no committed catalog at $CATALOG — run without --check first"
  status=0

  old_build=$(jq -r '.build' "$CATALOG")
  if [ "$old_build" != "$BUILD" ]; then
    note "DRIFT: software build changed: ${old_build} -> ${BUILD}"
    status=1
  fi

  old_cmds=$(jq -r '.commands | keys[]' "$CATALOG" | sort)
  new_cmds=$(printf '%s' "$NEW_CATALOG" | jq -r '.commands | keys[]' | sort)

  added=$(comm -13 <(printf '%s\n' "$old_cmds") <(printf '%s\n' "$new_cmds") | sed '/^$/d')
  removed=$(comm -23 <(printf '%s\n' "$old_cmds") <(printf '%s\n' "$new_cmds") | sed '/^$/d')
  if [ -n "$added" ]; then
    note "DRIFT: commands added on the CE:"
    printf '  + %s\n' $added >&2
    status=1
  fi
  if [ -n "$removed" ]; then
    note "DRIFT: commands no longer on the CE:"
    printf '  - %s\n' $removed >&2
    status=1
  fi

  if ! diff <(jq -S '.commands' "$CATALOG") \
    <(printf '%s' "$NEW_CATALOG" | jq -S '.commands') >/dev/null; then
    note "DRIFT: command metadata (category/tier/example/scope) changed:"
    diff <(jq -S '.commands' "$CATALOG") \
      <(printf '%s' "$NEW_CATALOG" | jq -S '.commands') >&2 || true
    status=1
  fi

  if [ "$status" -eq 0 ]; then
    note "catalog matches the live CE (build ${BUILD}, $(printf '%s\n' "$new_cmds" | wc -l | tr -d ' ') commands)"
  fi
  exit "$status"
fi

# --- write the catalog -------------------------------------------------------
mkdir -p "$OUT_DIR"
printf '%s\n' "$NEW_CATALOG" >"$CATALOG"
note "catalog: build ${BUILD}, $(jq -r '.commands | length' "$CATALOG") commands -> ${CATALOG#"${REPO_ROOT}/"}"

[ "$MODE" = "discover" ] && exit 0

# --- capture -----------------------------------------------------------------
[ -f "$MANIFEST" ] || die "missing $MANIFEST — it supplies the runnable arguments"
mkdir -p "$CAPTURE_DIR"

# Some commands need a real argument that only exists on the node right now. The
# resolvers below produce one; the captured output is a sample, and the pages say so.
resolve_args() {
  local cmd="$1" resolver id
  resolver=$(jq -r --arg c "$cmd" '.commands[$c].args_from // empty' "$MANIFEST")
  case "$resolver" in
  "") jq -r --arg c "$cmd" '(.commands[$c].args // []) | @json' "$MANIFEST" ;;
  first-crio-container)
    id=$(exec_user_raw crictl-ps '[]' | awk 'NR==2 {print $1}')
    [ -n "$id" ] || return 1
    jq -nc --arg id "$id" '[$id]'
    ;;
  first-docker-container)
    # The CE runs Docker AND CRI-O side by side: vpm, argo_watch and
    # site-console are Docker containers while the Kubernetes workloads are
    # CRI-O. Both families of command therefore return real output.
    id=$(exec_user_raw docker-ps '[]' | awk 'NR==2 {print $1}')
    [ -n "$id" ] || return 1
    jq -nc --arg id "$id" '[$id]'
    ;;
  *) die "unknown args_from resolver for ${cmd}: ${resolver}" ;;
  esac
}

# Captured text is trimmed to keep the documentation readable and the diffs
# reviewable: nh alone is 3849 lines. A trimmed capture ends with an explicit
# marker so a reader is never shown a truncated table as if it were complete.
# "max_lines": 0 in the manifest means keep everything.
trim_capture() {
  local cmd="$1" limit total
  limit=$(jq -r --arg c "$cmd" '.commands[$c].max_lines // empty' "$MANIFEST")
  [ -n "$limit" ] || limit=$(jq -r '.defaults.max_lines // 60' "$MANIFEST")
  if [ "$limit" = "0" ]; then
    cat
    return
  fi
  local body
  body=$(cat)
  total=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
  if [ "$total" -le "$limit" ]; then
    printf '%s\n' "$body"
  else
    # awk rather than `head`: head closes the pipe as soon as it has its lines,
    # which sends SIGPIPE upstream and trips `set -o pipefail`.
    printf '%s\n' "$body" | awk -v n="$limit" 'NR <= n'
    printf '\n... [capture trimmed: first %s of %s lines]\n' "$limit" "$total"
  fi
}

exec_user_raw() {
  local cmd="$1" extra="$2" argv
  argv=$(jq -nc --arg c "$cmd" --argjson e "$extra" '[$c] + $e')
  api POST "${SITE_BASE}/vpm/debug/${NODE}/exec-user" \
    "$(jq -nc --arg ns "$NAMESPACE" --arg s "$SITE" --arg n "$NODE" --argjson cmd "$argv" \
      '{namespace:$ns, site:$s, node:$n, command:$cmd}')" |
    jq -r 'if .output then .output else "ERROR: " + (.message // "no output") end'
}

captured=0 skipped=0 failed=0
while IFS=$'\t' read -r cmd tier scope; do
  case "$tier" in
  Exec)
    note "skip  ${cmd} (Exec tier — privileged or mutating, never executed)"
    skipped=$((skipped + 1))
    continue
    ;;
  esac

  if [ "$(jq -r --arg c "$cmd" '.commands[$c].skip // empty' "$MANIFEST")" != "" ]; then
    note "skip  ${cmd} ($(jq -r --arg c "$cmd" '.commands[$c].skip' "$MANIFEST"))"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$scope" = "GLOBAL" ]; then
    # Rule 1: dedicated GET endpoint, JSON body.
    # .txt even though the body is JSON. Every capture is evidence, not project
    # source, and a .json extension makes Biome lint it as source and demand its
    # own formatting. The MDX fence declares the language for rendering, so the
    # extension carries no information we need.
    dest="${CAPTURE_DIR}/sitecli-${cmd}.txt"
    if api GET "${SITE_BASE}/vpm/debug/global/${cmd}" | jq -S . 2>/dev/null | bash "$SCRUB" >"${dest}.tmp"; then
      mv "${dest}.tmp" "$dest"
      note "ok    ${cmd} (GLOBAL) -> ${dest#"${REPO_ROOT}/"}"
      captured=$((captured + 1))
    else
      rm -f "${dest}.tmp"
      note "FAIL  ${cmd} (GLOBAL)"
      failed=$((failed + 1))
    fi
    continue
  fi

  # Rule 2: exec-user, text body.
  if ! extra=$(resolve_args "$cmd"); then
    note "FAIL  ${cmd} (could not resolve an argument)"
    failed=$((failed + 1))
    continue
  fi
  dest="${CAPTURE_DIR}/sitecli-${cmd}.txt"
  out=$(exec_user_raw "$cmd" "$extra")
  case "$out" in
  ERROR:*)
    note "FAIL  ${cmd}: ${out}"
    failed=$((failed + 1))
    continue
    ;;
  esac
  printf '%s\n' "$out" | bash "$SCRUB" | trim_capture "$cmd" >"$dest"
  note "ok    ${cmd} -> ${dest#"${REPO_ROOT}/"}"
  captured=$((captured + 1))
done < <(jq -r '.commands | to_entries[] | [.key, .value.tier, (.value.scope // "")] | @tsv' "$CATALOG")

note ""
note "captured ${captured}, skipped ${skipped}, failed ${failed}"
[ "$failed" -eq 0 ] || exit 1
