#!/usr/bin/env bash
# Filter that every captured Customer Edge command output passes through before it
# is written into the repository. Reads stdin, writes stdout.
#
#   bash scripts/sitecli-scrub.sh <raw.txt >clean.txt
#
# TWO PROFILES, and strict is the DEFAULT.
#
#   SITECLI_SCRUB_PROFILE=strict   (default) assume the output came from a customer
#   SITECLI_SCRUB_PROFILE=lab                assume F5-owned demo infrastructure
#
# For a company customer, infrastructure identifiers ARE personally identifiable
# information: internal addressing, MAC addresses, AS numbers and hostnames all
# identify the organisation. Strict is the default so that pointing the harness at a
# customer node and committing the result cannot leak by omission — the dangerous
# direction requires an explicit choice, the safe one requires nothing. This
# repository declares `lab` in sitecli/capture-manifest.json, where the choice shows
# up in a diff.
#
# Removed under BOTH profiles:
#   API and bearer tokens, private key bodies
#   the tenant console hostname, and the tenant label inside internal SA names
#   object UUIDs, the Azure VNet DNS label
#   public IPv4 and global-unicast IPv6
#   email addresses, and home directories carrying an account name
#
# Removed under strict ONLY, kept under lab because there it is the diagnostic
# content rather than a customer's identity:
#   RFC1918 and RFC6598 addressing, MAC addresses, AS numbers, node and site names
#
# Kept under BOTH, because removing it would leave the output meaningless:
#   0.0.0.0          default routes, wildcard listen sockets
#   255.255.255.0    netmasks
#   255.255.255.255  broadcast
#   224.0.0.0/4      OSPF/BGP/VRRP multicast groups
#   127/8 169.254/16 loopback and link-local
#   fe80::/10 fc00::/7 ::1                        IPv6 equivalents
#   well-known public resolvers                   dig output, discloses nothing
#   container ids, build strings, interface names, tunnel state
#
# The address rules are enumerated rather than inferred precisely because a
# "looks public, redact it" heuristic destroys the four cases at the top of that
# last list. See tests/test-sitecli-scrub.sh — most of its cases assert preservation.
#
# Known limitation: a BGP neighbour table prints the AS as a bare column with no
# label, so ASNs are matched by value against the private ranges. A PUBLIC ASN in
# that column survives strict. Recorded in sitecli/README.md.
#
# The filter is idempotent under both profiles: every replacement emits a
# placeholder that cannot itself match the pattern that produced it.
set -euo pipefail

awk -v tenant="${SITECLI_TENANT:-}" \
  -v profile="${SITECLI_SCRUB_PROFILE:-strict}" \
  -v node="${SITECLI_NODE:-}" \
  -v site="${SITECLI_SITE:-}" '
# --- IPv4 classification -----------------------------------------------------
# Returns 1 when the dotted quad must be preserved.
function ipv4_preserve(a, b, c, d) {
  if (a == 0)                      return 1   # 0.0.0.0/8 — default route
  if (a == 127)                    return 1   # loopback
  if (a >= 224)                    return 1   # multicast, reserved, broadcast, masks
  if (a == 169 && b == 254)        return 1   # link-local
  if (a == 192 && b == 0 && c == 2)      return 1 # RFC5737 documentation
  if (a == 198 && b == 51 && c == 100)   return 1 # RFC5737 documentation
  if (a == 203 && b == 0 && c == 113)    return 1 # RFC5737 documentation
  if (a == 198 && b >= 18 && b <= 19)    return 1 # RFC2544 benchmarking

  # Internal addressing. For a company customer this identifies the organisation,
  # so the strict profile removes it; the lab profile keeps it because our own
  # captures come from F5-owned demo infrastructure and the addressing is the
  # diagnostic content.
  if (a == 10)                     return LAB  # RFC1918
  if (a == 172 && b >= 16 && b <= 31) return LAB # RFC1918
  if (a == 192 && b == 168)        return LAB  # RFC1918
  if (a == 100 && b >= 64 && b <= 127) return LAB # RFC6598 — XC internal space
  return 0
}

function is_known_resolver(ip) {
  return (ip in RESOLVERS)
}

# Replace a hostname and any truncation of it down to MIN_HOST_PREFIX characters.
function redact_host(line, name, placeholder,   i) {
  if (name == "") return line
  for (i = length(name); i >= MIN_HOST_PREFIX; i--) {
    gsub(substr(name, 1, i), placeholder, line)
  }
  return line
}

# Private AS ranges, redacted by value because a BGP neighbour table prints the AS
# as a bare column with no label for a rule to anchor on. Public ASNs in that same
# column are NOT caught this way — see the limitation noted in sitecli/README.md.
function is_private_asn(n) {
  if (n >= 64512 && n <= 65534) return 1          # RFC6996 16-bit
  if (n >= 4200000000 && n <= 4294967294) return 1 # RFC6996 32-bit
  return 0
}

function scrub_asn(line,   out, rest, tok, pre, post) {
  out = ""
  rest = line
  while (match(rest, /[0-9]+/)) {
    pre = substr(rest, 1, RSTART - 1)
    tok = substr(rest, RSTART, RLENGTH)
    post = substr(rest, RSTART + RLENGTH)
    if (is_private_asn(tok + 0)) out = out pre "<asn>"
    else out = out pre tok
    rest = post
  }
  return out rest
}

# True for the internal ranges, so a redacted one can be labelled <private-ip>
# rather than misreported as public.
function is_internal(a, b) {
  if (a == 10) return 1
  if (a == 172 && b >= 16 && b <= 31) return 1
  if (a == 192 && b == 168) return 1
  if (a == 100 && b >= 64 && b <= 127) return 1
  return 0
}

# Rewrite every IPv4 literal on the line that is ours.
function scrub_ipv4(line,   out, rest, m, ip, parts, n, pre, post) {
  out = ""
  rest = line
  while (match(rest, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
    pre = substr(rest, 1, RSTART - 1)
    ip  = substr(rest, RSTART, RLENGTH)
    post = substr(rest, RSTART + RLENGTH)

    # Reject a quad that is part of a longer dotted-numeric run (OIDs, SNMP).
    if (pre ~ /[0-9]\.$/ || post ~ /^\.[0-9]/) {
      out = out pre ip
      rest = post
      continue
    }

    n = split(ip, parts, ".")
    if (parts[1] > 255 || parts[2] > 255 || parts[3] > 255 || parts[4] > 255) {
      out = out pre ip                      # not a valid address
    } else if (is_known_resolver(ip)) {
      out = out pre ip
    } else if (ipv4_preserve(parts[1], parts[2], parts[3], parts[4])) {
      out = out pre ip
    } else if (is_internal(parts[1], parts[2])) {
      out = out pre "<private-ip>"
    } else {
      out = out pre "<public-ip>"
    }
    rest = post
  }
  return out rest
}

# --- IPv6 classification -----------------------------------------------------
# Only global unicast (2000::/3) is ours to hide. Everything else — loopback,
# link-local, unique-local — is fabric detail worth keeping. MAC addresses also
# contain colons, so a token only counts as IPv6 if it has a "::" run or a
# hextet longer than two digits; that excludes every well-formed MAC.
function scrub_ipv6(line,   out, rest, tok, pre, post, first) {
  out = ""
  rest = line
  while (match(rest, /[0-9A-Fa-f:]*:[0-9A-Fa-f:]*:[0-9A-Fa-f:]*/)) {
    pre  = substr(rest, 1, RSTART - 1)
    tok  = substr(rest, RSTART, RLENGTH)
    post = substr(rest, RSTART + RLENGTH)

    if (tok !~ /::/ && tok !~ /(^|:)[0-9A-Fa-f]{3,4}(:|$)/) {
      out = out pre tok                     # a MAC, or a plain colon list
      rest = post
      continue
    }

    # Leading hextet: empty for "::1", otherwise the text before the first colon.
    first = tok
    sub(/:.*/, "", first)
    if (first != "" && first ~ /^[23]/) {
      out = out pre "<public-ipv6>"
    } else {
      out = out pre tok
    }
    rest = post
  }
  return out rest
}

BEGIN {
  # LAB is 1 only under the lab profile, and is what ipv4_preserve returns for the
  # internal ranges. Strict is the default: pointing this at a customer node and
  # committing the result must not leak by omission, so the dangerous direction
  # needs an explicit flag and the safe one needs nothing.
  LAB = (profile == "lab") ? 1 : 0
  MIN_HOST_PREFIX = 8

  # Addresses that keep their identity because they are the same for everyone and
  # so identify nothing, while being meaningful where they appear:
  #   - well-known public resolvers, in dig output
  #   - 168.63.129.16, the Azure platform DNS and wireserver address, published
  #     by Microsoft and identical in every subscription. Real diagnosis output
  #     lists it as the nameserver for the node.
  split("8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9 149.112.112.112 " \
        "208.67.222.222 208.67.220.220 168.63.129.16", _r, " ")
  for (i in _r) RESOLVERS[_r[i]] = 1
  in_key = 0
}

{
  line = $0

  # Normalisation, so captured output satisfies the repository .editorconfig
  # (lf endings, no trailing whitespace, final newline) which is enforced in CI.
  # Column padding and the CRLF that curl echoes from HTTP headers are invisible
  # in a rendered code block, so nothing diagnostic is lost, and re-captures diff
  # much more cleanly. Interior blank lines are untouched: BGP output opens with
  # one and several captures use them to separate tables.
  # gsub, not sub(/\r$/): `curl -v` drives a progress meter with LONE carriage
  # returns, which awk does not treat as line breaks, so they sit mid-line where
  # an end-anchored rule never sees them.
  gsub(/\r/, "", line)
  sub(/[[:space:]]+$/, "", line)

  # Private key material: drop the body, keep the envelope so the reader can see
  # that something was elided rather than wondering what the block was.
  if (line ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) { in_key = 1; print line; next }
  if (in_key) {
    if (line ~ /-----END [A-Z ]*PRIVATE KEY-----/) { in_key = 0; print "<redacted>"; print line }
    next
  }

  # Credentials. Anchored on the scheme name so the placeholder cannot re-match.
  gsub(/APIToken[[:space:]]+[A-Za-z0-9+\/=_.-]+/, "APIToken <redacted>", line)
  gsub(/[Bb]earer[[:space:]]+[A-Za-z0-9+\/=_.-]+/, "Bearer <redacted>", line)

  # Tenant identity. "<tenant>" contains characters outside [a-z0-9-], so a second
  # pass leaves it alone.
  gsub(/[a-z0-9][a-z0-9-]*\.console\.ves\.volterra\.io/, \
       "<tenant>.console.ves.volterra.io", line)

  # The Azure-assigned VNet DNS label is unique to our deployment. The suffix is
  # kept so the reader can still tell what kind of name this is; the same
  # placeholder-cannot-rematch property applies.
  gsub(/[a-z0-9]+\.bx\.internal\.cloudapp\.net/, \
       "<vnet-dns-label>.bx.internal.cloudapp.net", line)

  # The tenant also appears inside the internal SA names that ipsec-status and
  # health print, carrying a unique suffix: <tenant>-<suffix>. The console-hostname
  # rule above never saw those, so real captures were publishing it. Passed in via
  # SITECLI_TENANT rather than hardcoded, so this works for any tenant; with none
  # set, nothing is substituted. Longest form first, so the suffixed label is
  # consumed before the bare name can match its prefix.
  if (tenant != "") {
    gsub(tenant "-[A-Za-z0-9]+", "<tenant>", line)
    gsub(tenant, "<tenant>", line)
  }

  # Internal object UUIDs identify tenant resources and carry no value in docs. The
  # surrounding name is kept, so an SA line still shows which regional edge the
  # tunnel terminates on.
  gsub(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/, \
       "<uuid>", line)

  # --- PII, removed under BOTH profiles ---------------------------------------
  # Email addresses, and home directories which carry an account name. Both can
  # appear in journal lines, container environments and inspect output.
  gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/, "<email>", line)
  # Handled as two separate rules because awk gsub has no backreferences, so the
  # prefix cannot be carried through a single alternation.
  gsub(/\/home\/[A-Za-z0-9._-]+/, "/home/<user>", line)
  gsub(/\/Users\/[A-Za-z0-9._-]+/, "/Users/<user>", line)

  # --- strict profile: infrastructure identity is customer PII ----------------
  if (!LAB) {
    # Hostnames. The node and site are supplied by the caller, so this catches
    # netstat host:port columns and log prefixes that no address rule would see.
    # Longest form first, then progressively shorter prefixes: netstat truncates the
    # hostname to fit its column ("f5-xc-ce-" for "f5-xc-ce-vm-01"), so an exact
    # match alone silently misses it. The floor of 8 characters keeps a short prefix
    # from swallowing unrelated text.
    line = redact_host(line, node, "<node>")
    line = redact_host(line, site, "<site>")

    # MAC addresses: six two-hex groups, which is what excludes IPv6.
    gsub(/[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f]){5}/, "<mac>", line)

    # AS numbers identify the organisation in any BGP output. Two rules: the
    # labelled form, and private ranges by value for the bare neighbour-table column.
    gsub(/(remote AS|local AS number|AS)[[:space:]]+[0-9]+/, "AS <asn>", line)
    line = scrub_asn(line)
  }

  line = scrub_ipv6(line)
  line = scrub_ipv4(line)

  print line
}
'
