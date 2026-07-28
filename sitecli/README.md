# Customer Edge Site CLI catalog and captures

Evidence for the Customer Edge diagnostics documentation. Everything here is
produced by `scripts/capture-sitecli.sh` from a live CE and is never hand-edited.

| Path | What it is |
| --- | --- |
| `catalog.json` | The command surface, discovered from the node. The stable contract. |
| `capture-manifest.json` | Runnable arguments, trim limits, and resolvers for capture. |
| `captures/` | Output of each read-only command, scrubbed. Dated evidence. |

Every capture is named `.txt`, including the two whose body is JSON. These files
are evidence rather than project source, and a `.json` extension makes Biome lint
them as source and demand its own formatting. The MDX fence sets the language for
rendering, so the extension carries nothing we need.

## Refreshing

```bash
bash scripts/capture-sitecli.sh                  # discover + capture
bash scripts/capture-sitecli.sh --discover-only  # refresh catalog.json only
bash scripts/capture-sitecli.sh --check          # drift gate, writes nothing
```

A site and a node must be resolved before any of those run. Supply `--site` and `--node`, or
set both `defaults.site` and `defaults.node` in `capture-manifest.json`; the script never
guesses, and exits telling you which is missing. Read the values from the deployment rather
than typing them:

```bash
cd terraform
SITE=$(terraform output -json xc_site_names | jq -r .eastus01)
NODE=$(terraform output -json ce_vm_names   | jq -r .eastus01)
cd .. && bash scripts/capture-sitecli.sh --check --site "$SITE" --node "$NODE"
```

This needs a live tenant, so it is a workstation operation: the F5 corporate Entra
tenant does not permit provisioning an Azure service principal, so no GitHub
runner can hold the credential. CI instead runs `scripts/check-sitecli-docs.sh`,
which is offline and proves the documentation agrees with `catalog.json`. The
committed catalog is CI's proxy for the live tenant; `--check` on a workstation is
what proves the catalog still matches reality.

### The on-box harness is a separate tool

`scripts/sitecli_ssh_harvest.py` reaches the larger `execcli` surface over SSH and writes
`exec-catalog.json`. It takes `--node` as an SLI address and `--jump` as an operator VM inside
the VNet, and records `--site-state` as provenance because a menu read in one registration
state is not evidence about another.

It reports progress every 25 scrolls. That matters: the completion menu shows six rows at a
time whatever the terminal size, so exhausting an 82-command menu takes about 101 keypresses,
and a silent run is indistinguishable from a stalled one. Teardown is bounded — SIGTERM, wait,
SIGKILL, wait — and `tests/test-sitecli-harvest.sh` fails if an unbounded wait is reintroduced.

## Three routing rules

The catalog entry for each command is `[category, tier, exampleArg?, scope?]`, and
those fields decide how the command is reached. All three rules were established
by probing the live API — none of this is documented upstream.

| Condition | Transport | Returns |
| --- | --- | --- |
| `scope` is `GLOBAL` | `GET .../vpm/debug/global/<cmd>` | JSON |
| `tier` is `ExecUser` | `POST .../vpm/debug/<node>/exec-user` | text |
| `tier` is `Exec` | `POST .../vpm/debug/<node>/exec` | never called |

Two traps worth knowing:

- A `GLOBAL` command is **not** reachable through `exec-user`, which answers
  `command not supported`. Only `health` and `diagnosis` are `GLOBAL`.
- Discovery works by **omitting** the `command` key. Sending an unknown command
  value returns an error rather than the catalog.

`Exec` is privileged: every member either mutates the node or reads a state
marker. `capture-sitecli.sh` refuses to execute that tier, reading the tier from
the live catalog rather than a hardcoded list, so a build that promotes a command
to `Exec` is respected without a code change.

## Scrubbing, and why strict is the default

Captures pass through `scripts/sitecli-scrub.sh`, which has two profiles.

**For a company customer, infrastructure identifiers are personally identifiable
information.** Internal addressing, MAC addresses, AS numbers and hostnames all
identify the organisation. So the filter defaults to `strict`, which removes them:
pointing this harness at a customer node and committing the result cannot leak by
omission. The dangerous direction takes an explicit choice; the safe one takes
nothing.

This repository declares `lab` in `capture-manifest.json`, because its captures
come from an F5-owned demo tenant covered by the authorized-use statement in
`CLAUDE.md`, and there the addressing *is* the diagnostic content. That declaration
lives in the manifest rather than in the script so it appears in a diff and has to
be reviewed. **Capturing from a customer node: do not set it.**

| | `strict` (default) | `lab` |
| --- | --- | --- |
| RFC1918 / RFC6598 addressing | `<private-ip>` | kept |
| MAC addresses | `<mac>` | kept |
| AS numbers | `<asn>` | kept |
| Node and site names | `<node>` / `<site>` | kept |

Removed under **both** profiles: API and bearer tokens, private key bodies, the
tenant console hostname, the tenant label inside internal SA names, object UUIDs,
the Azure VNet DNS label, public IPv4 and global-unicast IPv6, email addresses, and
home directories carrying an account name.

Kept under both, because removing it leaves the output meaningless: `0.0.0.0`,
netmasks, broadcast, multicast groups, loopback, link-local, well-known public
resolvers, container ids, build strings, interface names and tunnel state.

Two rules exist only because real output disproved an assumption:

- Hostnames are also matched as **truncations** down to 8 characters, because
  `netstat` shortens them to fit its column (`f5-xc-ce-` for `f5-xc-ce-vm-01`) and an
  exact-match rule silently missed it.
- The tenant appears inside internal IPsec SA names with a unique suffix, which the
  console-hostname rule never saw.

See `tests/test-sitecli-scrub.sh` — 82 assertions, and most of them assert
*preservation*, because over-redaction is the failure mode that makes a capture
worthless.

### Known limitation

A BGP neighbour table prints the AS as a bare column with no label to anchor on, so
ASNs are matched **by value** against the private ranges (RFC6996 16-bit and
32-bit). A **public** ASN in that column survives `strict`. If you capture from a
customer using public ASNs, review `show-ip-bgp*` output by hand before committing
it.

Captured text is trimmed to keep pages readable (`nh --list` alone is 3849
lines). A trimmed capture ends with an explicit
`... [capture trimmed: first N of M lines]` marker, so a truncated table is never
presented as if it were complete.

## Writing the documentation pages

Four rules are enforced by tests, so they are not style preferences.

**No deployment-specific value inside a `bash` or `sh` fence.** A literal in a command is an
instruction, and it is wrong for every deployment but one — silently, because a resource group
that does not exist looks the same as a mistyped command. Read it instead:

```bash
terraform -chdir=terraform output -raw resource_group_name
terraform -chdir=terraform output -json ce_sli_private_ips
```

**Any page that shows a live value must carry `Observed YYYY-MM-DD` or `Captured
YYYY-MM-DD`.** Captured output is welcome; *undated* captured output is not, because a reader
cannot tell whether it was true today or three rebuilds ago. Both rules are checked by
`tests/test-docs-no-literals.sh`.

**MDX parses `<word>` as a JSX tag.** A placeholder like `r-<uuid>` in prose fails the build
with `Expected a closing tag`. Backtick it. Related: if `textlint --plugin mdx` cannot parse a
page, that is a *true signal* of this and not a plugin defect — the error text invites you to
report a plugin bug, and doing so wastes your time.

**Do not duplicate configuration that has to stay identical across locales.** Fenced code is
preserved — command names and captured output come through unchanged in all twelve locales,
verified. Frontmatter and prose are translated, so a `description` or heading carrying a
literal value will differ per locale. Import evidence through `docs/_imports` and `_data/`
rather than restating it in the page, and keep literals out of frontmatter.

### CI does not lint these pages

The shared linter runs `BASH`, `CHECKOV`, `GITLEAKS`, `JSCPD`, the Python set, `SHELL_SHFMT`,
`SPELL_CODESPELL` and `TRIVY` — there is **no `MARKDOWN` entry at all**, so neither
markdownlint nor textlint sees `docs/`. Run them yourself:

```bash
npx --yes markdownlint-cli@latest -c .markdownlint.json $(find docs/en -name '*.mdx')
npx --yes -p textlint@15.7.1 -p textlint-rule-terminology -p textlint-plugin-mdx \
  textlint --plugin mdx -c .textlintrc -f compact $(find docs/en -name '*.mdx')
```

textlint reports three standing false positives, all link text where the lowercase spelling is
the page or command name — `[curl](…)` once and `[docker](…)` twice. Anything beyond those
three is worth reading: the count was four when these notes were written, and the fourth was a
real terminology error in prose.

## Known gaps

- **Two of the 33 captures are not committed yet**, both blocked on
  `f5-sales-demo/docs-control#795`:

  - `captures/sitecli-show-ip-bgp-neighbors.txt`
  - `captures/sitecli-journalctl.txt`

  In its Graceful Restart line, FRR prints "Capability" with the second `i`
  missing, and vpm echoes the same line into the journal. `codespell` rejects both
  files. Correcting the captured text would make the documentation describe output
  that never occurred, and `.codespellrc` is governance-managed, so the fix belongs
  upstream: #795 adds that word to `ignore-words-list`.

  Both captures *succeed*; only committing them is blocked. Re-run
  `capture-sitecli.sh` once #795 lands. Until then the BGP neighbours and vpm log
  pages cannot carry embedded evidence — which the consistency gate will report,
  because a page referencing a missing capture is a violation.

  The word cannot be quoted verbatim in these notes either, for the same reason.
- **Whether the advertised newer build installs on this topology is unsettled**, which is why
  the command reference documents `crt-20250613-3382` only.

  The tenant advertises `crt-20260201-0179` (`volterra_software_status.available_version` on
  the site object). Two observations conflict and neither can now be confirmed:

  - It was reported to fail on single-node Azure Secure Mesh v2 sites, with all three nodes
    stopping at the `voucher` DaemonSet while the OS upgrade to `9.2026.14` succeeded.
  - A `CUSTOMER_EDGE` site was earlier observed running that exact build, `ONLINE`, in another
    tenant. That site no longer exists, so its type cannot be re-checked — the failure may have
    involved the discontinued App Stack site type rather than a plain CE.

  What would settle it: deploy one CE pinned to that build from scratch and see whether it
  registers, which separates "fails to upgrade in place" from "fails to install at all". Since
  a version change is a fleet rebuild, this is not a cheap experiment; do not start it to
  satisfy curiosity about the newer commands.

- Output for the nine commands that exist only on newer CE builds is absent, since
  this tenant runs `crt-20250613-3382`. They are recorded by name and tier only.
