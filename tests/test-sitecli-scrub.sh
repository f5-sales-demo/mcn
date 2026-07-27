#!/usr/bin/env bash
# Hermetic test for scripts/sitecli-scrub.sh — the filter every captured CE
# command output passes through before it is written to the repository.
#
# The scrub has two jobs that pull against each other:
#
#   1. Never publish anything that identifies our tenant or our infrastructure:
#      API tokens, the tenant console hostname, our public addresses, private keys.
#   2. Never damage the diagnostic content that makes the capture worth publishing.
#      A naive "looks like a public IP" rule eats `0.0.0.0` from a default route,
#      `255.255.255.0` from a netmask, and `224.0.0.5` from an OSPF/BGP neighbour
#      line — which is most of the value of `rt`, `ip addr` and the BGP commands.
#
# Job 2 is why the address rules below are enumerated rather than inferred, and
# why the majority of these cases assert that something is *preserved*.
#
# No network. Operates on strings only.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/sitecli-scrub.sh"

FAIL=0

# scrub <text> — run the filter under the LAB profile, which is what this
# repository publishes: its captures come from F5-owned demo infrastructure, where
# internal addressing and MAC addresses are the diagnostic content rather than a
# customer's identity. The profile is named explicitly because the DEFAULT is
# strict; a separate assertion below pins that default.
scrub() { printf '%s' "$1" | SITECLI_SCRUB_PROFILE=lab bash "$SCRIPT"; }

# assert_preserved <label> <text> <needle>
# The needle must survive the scrub verbatim.
assert_preserved() {
  local label="$1" text="$2" needle="$3" out
  out=$(scrub "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[OK] $label -> preserved"
  else
    echo "[FAIL] $label — expected '$needle' to survive, got: $out"
    FAIL=1
  fi
}

# assert_removed <label> <text> <needle>
# The needle must not appear anywhere in the output.
#
# The input is checked first: a removal assertion whose fixture never contained
# the needle passes for free and proves nothing. That is not hypothetical — the
# tenant fixture below was rewritten to a placeholder while the tenant the filter
# was told to redact stayed behind, and the assertion went on passing until the
# two drifted far enough apart to fail for an unrelated reason.
assert_removed() {
  local label="$1" text="$2" needle="$3" out
  if ! printf '%s' "$text" | grep -qF -- "$needle"; then
    echo "[FAIL] $label — fixture does not contain '$needle', so this asserts nothing"
    FAIL=1
    return
  fi
  out=$(scrub "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[FAIL] $label — expected '$needle' to be removed, got: $out"
    FAIL=1
  else
    echo "[OK] $label -> removed"
  fi
}

# --- secrets: the whole point of the filter ------------------------------------
# Fixtures below are DELIBERATELY fake and obviously so. An earlier version of this
# file used real tenant API tokens because they made "realistic" fixtures, and
# committed them to a public repository — in the very test that asserts tokens are
# redacted. gitleaks did not catch them: the format matches none of its rules. Keep
# these values self-evidently synthetic.
assert_removed "API token in an Authorization header" \
  'Authorization: APIToken EXAMPLEtoken0000NotARealValue=' 'EXAMPLEtoken0000NotARealValue='
assert_removed "bare APIToken value" \
  'curl -H "Authorization: APIToken EXAMPLEsecond0000NotARealValue=" https://x' 'EXAMPLEsecond0000NotARealValue='
assert_removed "Bearer token" \
  'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def' 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
assert_removed "private key body" \
  '-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAx7Vk2mFakePrivateKeyMaterialHere
-----END RSA PRIVATE KEY-----' 'MIIEowIBAAKCAQEAx7Vk2mFakePrivateKeyMaterialHere'

# --- tenant identity -----------------------------------------------------------
# The console-hostname rule matches on shape, not on a configured value, so these
# two fixtures need no tenant set and deliberately name no real tenant.
assert_removed "tenant console hostname" \
  'endpoint https://example-tenant.console.ves.volterra.io/api' 'example-tenant.console'
assert_removed "second tenant console hostname" \
  'endpoint https://another-tenant.console.ves.volterra.io/api' 'another-tenant.console'

# The tenant also appears, with a unique suffix, inside the internal IPsec SA names
# that `ipsec-status` and `health` print. The console-hostname rule never saw these,
# so real captures were publishing the tenant identifier. The tenant is passed in
# rather than hardcoded, so this generalises to any tenant.
#
# The fixtures below are built from $SITECLI_TENANT rather than repeating it, and
# assert_tenant_removed refuses a fixture that does not contain it. Both guards
# exist because the literal and the configured value drifted apart once already:
# a bulk rewrite replaced the tenant label inside the fixture and left the exported
# tenant behind, leaving an assertion that asked the filter to redact a string it
# had never been told about.
SITECLI_TENANT=example-tenant
export SITECLI_TENANT
TENANT_SA="ver.ar-bgp-eastus01.${SITECLI_TENANT}-a1b2c3d4.32809c43-6b26-4f07-a59b-b023ab1587f1.tenant.int.ves.io"

# assert_tenant_removed <label> <text> <needle>
# As assert_removed, but the fixture must exercise the configured tenant.
assert_tenant_removed() {
  local label="$1" text="$2" needle="$3"
  if [ -z "${SITECLI_TENANT:-}" ]; then
    echo "[FAIL] $label — SITECLI_TENANT is unset, so the tenant rule cannot fire"
    FAIL=1
    return
  fi
  if ! printf '%s' "$text" | grep -qF -- "$SITECLI_TENANT"; then
    echo "[FAIL] $label — fixture does not contain the configured tenant '$SITECLI_TENANT'"
    FAIL=1
    return
  fi
  assert_removed "$label" "$text" "$needle"
}

assert_tenant_removed "tenant label with unique suffix in an IPsec SA name" \
  "${TENANT_SA}[47]" "${SITECLI_TENANT}-a1b2c3d4"
assert_tenant_removed "bare tenant name" \
  "site belongs to tenant ${SITECLI_TENANT} today" "$SITECLI_TENANT"
assert_preserved "SA name keeps its shape" "${TENANT_SA}[47]" 'tenant.int.ves.io'
assert_preserved "site name inside an SA name survives" "$TENANT_SA" 'ar-bgp-eastus01'

# Internal object UUIDs identify tenant resources and carry no documentation value.
assert_removed "object UUID" \
  'reqid ver.dc12-ash.ves-io.23f7c41e-4c3d-40fd-bdc9-66502f6b206c.tenant.int.ves.io' \
  '23f7c41e-4c3d-40fd-bdc9-66502f6b206c'

# F5 regional edge POP names are public infrastructure and are the useful part of
# an SA line: they say which RE the tunnel terminates on.
assert_preserved "regional edge POP name" \
  'ver.ny8-nyc.ves-io.dea340b4-2c36-414b-ad3d-3da706accbda.tenant.int.ves.io' 'ny8-nyc'
unset SITECLI_TENANT

# With no tenant supplied the filter must still run, and must not invent a match.
assert_preserved "no tenant configured leaves text alone" \
  'ver.ar-bgp-eastus01.some-tenant-abcd1234.tenant.int.ves.io' 'some-tenant-abcd1234'

# --- our public addresses ------------------------------------------------------
assert_removed "CE public IPv4" 'inet 20.124.35.231/32 scope global' '20.124.35.231'
assert_removed "second CE public IPv4" 'peer 168.62.59.17 up' '168.62.59.17'
assert_removed "global unicast IPv6" 'inet6 2603:1030:c02:3::17/128' '2603:1030:c02:3::17'

# --- addresses that MUST survive: this is where a careless rule does damage ----
assert_preserved "default route prefix" '0.0.0.0/0 via 10.0.1.1 dev eth0' '0.0.0.0/0'
assert_preserved "unspecified address in a listen socket" \
  'tcp 0 0 0.0.0.0:22 0.0.0.0:* LISTEN' '0.0.0.0:22'
assert_preserved "netmask" 'inet 10.0.1.4 netmask 255.255.255.0' '255.255.255.0'
assert_preserved "all-ones broadcast" 'broadcast 255.255.255.255' '255.255.255.255'
assert_preserved "OSPF/BGP multicast group" 'join group 224.0.0.5' '224.0.0.5'
assert_preserved "RFC1918 ten-dot" 'inet 10.0.1.4/24' '10.0.1.4'
assert_preserved "RFC1918 172.16/12" 'inet 172.16.5.9/24' '172.16.5.9'
assert_preserved "RFC1918 192.168/16" 'inet 192.168.1.1/24' '192.168.1.1'
assert_preserved "loopback" 'inet 127.0.0.1/8 scope host lo' '127.0.0.1'
assert_preserved "link-local" 'inet 169.254.1.1/16' '169.254.1.1'
assert_preserved "XC carrier-grade NAT space" 'flow match 100.127.192.10:53' '100.127.192.10'
assert_preserved "IPv6 loopback" 'inet6 ::1/128 scope host' '::1'
assert_preserved "IPv6 link-local" 'inet6 fe80::20d:3aff:fe7c:1/64' 'fe80::20d:3aff:fe7c:1'
assert_preserved "IPv6 unique local" 'inet6 fd00:1::5/64' 'fd00:1::5'

# Public resolvers carry documentation value and disclose nothing about us.
assert_preserved "Google public DNS in dig output" 'SERVER: 8.8.8.8#53(8.8.8.8)' '8.8.8.8'
assert_preserved "Cloudflare public DNS" ';; SERVER: 1.1.1.1#53' '1.1.1.1'

# Azure's platform DNS / wireserver address is published by Microsoft and is
# identical for every VM in every subscription, so it identifies nothing. It shows
# up in real `diagnosis` and `dig` output and is meaningful there.
assert_preserved "Azure platform DNS address" \
  'nameserver 168.63.129.16' '168.63.129.16'

# The Azure-assigned VNet DNS label, by contrast, is unique to our deployment.
# Taken from real `diagnosis` output.
assert_removed "Azure VNet DNS label" \
  'search w5yqtxiwsjfexcydw1s2fwarwa.bx.internal.cloudapp.net' \
  'w5yqtxiwsjfexcydw1s2fwarwa'
assert_preserved "Azure VNet DNS label keeps its shape" \
  'search w5yqtxiwsjfexcydw1s2fwarwa.bx.internal.cloudapp.net' \
  'internal.cloudapp.net'

# --- diagnostic content that is not secret and must not be mangled -------------
assert_preserved "CE software build string" \
  'Software Version: crt-20250613-3382' 'crt-20250613-3382'
assert_preserved "container id" \
  '89a5bee1ab6ce  feec7a48f9b4  2 days ago  Running' '89a5bee1ab6ce'
assert_preserved "site and node names" \
  'site ar-bgp-eastus01 node f5-xc-ce-vm-01 ONLINE' 'ar-bgp-eastus01'
assert_preserved "interface names" 'eth0 eth1 vhost0 tunnel0' 'vhost0'
assert_preserved "BGP AS numbers" 'BGP neighbor is 10.0.1.5, remote AS 65001' '65001'

# MAC addresses contain colons. A MAC whose first octet begins 2 or 3 is exactly
# what a "global unicast IPv6 starts with 2 or 3" rule mistakes for an address,
# so both the safe and the dangerous first octets are pinned here.
assert_preserved "MAC address, first octet 7c" \
  'link/ether 7c:1e:52:7f:f8:12 brd ff:ff:ff:ff:ff:ff' '7c:1e:52:7f:f8:12'
assert_preserved "MAC address, first octet 2c" \
  'link/ether 2c:54:91:88:c9:e3 brd ff:ff:ff:ff:ff:ff' '2c:54:91:88:c9:e3'
assert_preserved "MAC address, first octet 3a" \
  'link/ether 3a:0d:52:11:0e:07 brd ff:ff:ff:ff:ff:ff' '3a:0d:52:11:0e:07'
assert_preserved "all-ones MAC broadcast" \
  'link/ether 00:0d:3a:7c:00:01 brd ff:ff:ff:ff:ff:ff' 'ff:ff:ff:ff:ff:ff'

# --- profiles: strict is the default, lab must be asked for --------------------
# For a company customer, infrastructure identifiers ARE personally identifiable
# information: internal addressing, MAC addresses, AS numbers and hostnames all
# identify the organisation. The lab profile keeps them because this repository's
# own captures come from F5-owned demo infrastructure and their diagnostic value is
# the point. Strict is the DEFAULT so that pointing the harness at a customer node
# and committing the result cannot leak by omission — the dangerous direction
# requires an explicit flag, the safe one requires nothing.

# The node and site names are supplied by the caller — capture-sitecli.sh knows
# them — because no address rule can catch a hostname in a netstat column or a log
# prefix.
strict() {
  printf '%s' "$1" | SITECLI_SCRUB_PROFILE=strict \
    SITECLI_NODE=f5-xc-ce-vm-01 SITECLI_SITE=ar-bgp-eastus01 bash "$SCRIPT"
}

assert_strict_removed() {
  local label="$1" text="$2" needle="$3" out
  out=$(strict "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[FAIL] strict: $label — expected '$needle' removed, got: $out"
    FAIL=1
  else
    echo "[OK] strict: $label -> removed"
  fi
}

assert_strict_preserved() {
  local label="$1" text="$2" needle="$3" out
  out=$(strict "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[OK] strict: $label -> preserved"
  else
    echo "[FAIL] strict: $label — expected '$needle' to survive, got: $out"
    FAIL=1
  fi
}

# Default profile must be strict, with no environment variable set at all.
default_out=$(printf 'inet 10.0.1.4/24' | bash "$SCRIPT")
case "$default_out" in
*10.0.1.4*)
  echo "[FAIL] default profile leaked a private address — strict must be the default"
  FAIL=1
  ;;
*) echo "[OK] default profile is strict" ;;
esac

# Customer-identifying detail, removed under strict.
assert_strict_removed "RFC1918 address" 'inet 10.0.1.4/24 brd 10.0.1.63' '10.0.1.4'
assert_strict_removed "RFC1918 172.16/12" 'peer 172.16.5.9' '172.16.5.9'
assert_strict_removed "RFC1918 192.168/16" 'gw 192.168.1.1' '192.168.1.1'
assert_strict_removed "carrier-grade NAT address" 'flow 100.127.192.10:53' '100.127.192.10'
assert_strict_removed "MAC address" 'link/ether 7c:1e:52:7f:f8:12 brd ff:ff:ff:ff:ff:ff' '7c:1e:52:7f:f8:12'
assert_strict_removed "remote AS number" 'BGP neighbor is 10.0.1.5, remote AS 65515' '65515'
assert_strict_removed "local AS number" 'local AS number 64512 vrf-id 3' '64512'
assert_strict_removed "node hostname" \
  'tcp 0 0 f5-xc-ce-vm-01:57472 ESTABLISHED' 'f5-xc-ce-vm-01'
assert_strict_removed "site name" 'site ar-bgp-eastus01 is ONLINE' 'ar-bgp-eastus01'

# netstat truncates the hostname to fit its column, so the full name never appears
# and an exact-match rule silently misses it. Taken from real captured output.
assert_strict_removed "truncated hostname in a netstat column" \
  'tcp 0 0 f5-xc-ce-vm-01:53668 f5-xc-ce-:simplifymedia TIME_WAIT' 'f5-xc-ce-'
assert_strict_removed "hostname with a domain suffix appended" \
  'tcp 0 0 f5-xc-ce-vm-01.in:50810 10.0.1.9:9505 ESTABLISHED' 'f5-xc-ce-vm-01.in'
# A short prefix must NOT be treated as the hostname, or unrelated text is eaten.
assert_strict_preserved "short unrelated token is not mistaken for the hostname" \
  'f5 is the vendor' 'f5 is the vendor'

# The AS number in a BGP neighbour table is a bare column with no "AS" prefix, so
# the labelled rule never sees it. Private ASN ranges are redacted by value.
assert_strict_removed "bare private ASN in a neighbour table column" \
  '10.0.4.4        4      64512   43786   38399        0    0    0 2d05h18m   1' '64512'
assert_strict_removed "bare 4-byte private ASN" \
  '10.0.4.4        4  4200000001   100   200' '4200000001'
assert_strict_preserved "message counters are not mistaken for ASNs" \
  '10.0.4.4        4      64512   43786   38399' '43786'

# Structure and non-identifying values still survive, or strict output is useless.
assert_strict_preserved "default route under strict" '0.0.0.0/0 via 10.0.1.1' '0.0.0.0/0'
assert_strict_preserved "netmask under strict" 'netmask 255.255.255.0' '255.255.255.0'
assert_strict_preserved "multicast group under strict" 'join group 224.0.0.5' '224.0.0.5'
assert_strict_preserved "loopback under strict" 'inet 127.0.0.1/8' '127.0.0.1'
assert_strict_preserved "interface name under strict" 'vhost0 state UP' 'vhost0'
assert_strict_preserved "tunnel state under strict" 'INSTALLED, TUNNEL, reqid 65541' 'INSTALLED, TUNNEL'
assert_strict_preserved "build string under strict" 'Version crt-20250613-3382' 'crt-20250613-3382'

# The lab profile is what this repository publishes, and must keep the detail.
assert_preserved "lab profile keeps RFC1918" 'inet 10.0.1.4/24' '10.0.1.4'
assert_preserved "lab profile keeps MAC" 'link/ether 7c:1e:52:7f:f8:12' '7c:1e:52:7f:f8:12'
assert_preserved "lab profile keeps AS number" 'remote AS 65515' '65515'

# Strict must remain idempotent, like the lab profile.
s1=$(strict 'inet 10.0.1.4/24 mac 7c:1e:52:7f:f8:12 AS 65515')
s2=$(printf '%s' "$s1" | SITECLI_SCRUB_PROFILE=strict bash "$SCRIPT")
if [ "$s1" = "$s2" ]; then
  echo "[OK] strict: idempotent"
else
  echo "[FAIL] strict: not idempotent"
  echo "  once:  $s1"
  echo "  twice: $s2"
  FAIL=1
fi

# --- PII that must go under BOTH profiles --------------------------------------
assert_removed "email address" 'contact user@example.com for access' 'user@example.com'
assert_removed "macOS home directory" 'cache /Users/<USER>/.cache/thing' 'rmordasiewicz'
assert_removed "Linux home directory" 'export DATA=/home/<USER>/data' 'rmordasiewicz'
assert_preserved "home path keeps its shape" 'cache /Users/<USER>/.cache' '/Users/'

# --- whitespace normalisation --------------------------------------------------
# The repository .editorconfig requires LF endings, no trailing whitespace and a
# final newline, and the check is enforced in CI. Captured CLI output violates all
# three: tables are column-padded with trailing spaces and `curl -v` echoes HTTP
# headers with CRLF. Normalising here is the source fix. It costs no evidence —
# trailing padding and carriage returns are invisible in a rendered code block —
# and it also makes re-captures diff far more cleanly.
trailing=$(printf 'IF RX Discard   5   \nnext line\n' | bash "$SCRIPT" | grep -c ' $' || true)
if [ "$trailing" = "0" ]; then
  echo "[OK] trailing whitespace stripped"
else
  echo "[FAIL] $trailing line(s) still end in whitespace"
  FAIL=1
fi

if printf 'HTTP/1.1 200 OK\r\nServer: nginx\r\n' | bash "$SCRIPT" | grep -q $'\r'; then
  echo "[FAIL] carriage returns survived"
  FAIL=1
else
  echo "[OK] CRLF normalised to LF"
fi

# A final newline must be present exactly once, whether or not the input had one.
for probe in 'no trailing newline' 'has trailing newline
'; do
  out=$(printf '%s' "$probe" | bash "$SCRIPT" | od -c | tail -2 | head -1)
  case "$out" in
  *'\n'*) : ;;
  *)
    echo "[FAIL] no final newline for input: ${probe%%$'\n'*}"
    FAIL=1
    ;;
  esac
done
echo "[OK] final newline present"

# Interior blank lines are content and must not be collapsed: BGP output opens
# with one, and several captures separate tables that way.
blanks=$(printf 'a\n\n\nb\n' | bash "$SCRIPT" | wc -l | tr -d ' ')
if [ "$blanks" = "4" ]; then
  echo "[OK] interior blank lines preserved"
else
  echo "[FAIL] interior blank lines altered: expected 4 lines, got $blanks"
  FAIL=1
fi

# --- idempotence: capture re-runs must not re-rewrite already-scrubbed text ----
once=$(scrub 'inet 20.124.35.231/32 and https://f5-sales-demo.console.ves.volterra.io/api')
twice=$(printf '%s' "$once" | bash "$SCRIPT")
if [ "$once" = "$twice" ]; then
  echo "[OK] scrubbing is idempotent"
else
  echo "[FAIL] scrubbing is not idempotent"
  echo "  once:  $once"
  echo "  twice: $twice"
  FAIL=1
fi

# --- structure is preserved ----------------------------------------------------
lines_in=$(printf 'a\nb\nc\n' | bash "$SCRIPT" | wc -l | tr -d ' ')
if [ "$lines_in" = "3" ]; then
  echo "[OK] line count preserved"
else
  echo "[FAIL] line count changed: expected 3, got $lines_in"
  FAIL=1
fi

empty_rc=0
printf '' | bash "$SCRIPT" >/dev/null 2>&1 || empty_rc=$?
if [ "$empty_rc" -eq 0 ]; then
  echo "[OK] empty input succeeds"
else
  echo "[FAIL] empty input exited $empty_rc"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "sitecli-scrub tests FAILED"
  exit 1
fi
echo "sitecli-scrub tests passed"
