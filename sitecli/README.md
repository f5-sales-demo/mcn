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

This needs a live tenant, so it is a workstation operation: the F5 corporate Entra
tenant does not permit provisioning an Azure service principal, so no GitHub
runner can hold the credential. CI instead runs `scripts/check-sitecli-docs.sh`,
which is offline and proves the documentation agrees with `catalog.json`. The
committed catalog is CI's proxy for the live tenant; `--check` on a workstation is
what proves the catalog still matches reality.

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

## Scrubbing

Captures pass through `scripts/sitecli-scrub.sh`, which removes API tokens, the
tenant console hostname, our public addresses, the Azure VNet DNS label and
private key material, while deliberately preserving the content that makes the
output worth reading: `0.0.0.0`, netmasks, multicast groups, RFC1918 and
carrier-grade NAT addresses, MAC addresses, and well-known public resolvers. See
`tests/test-sitecli-scrub.sh`, where most cases assert preservation.

Captured text is trimmed to keep pages readable (`nh --list` alone is 3849
lines). A trimmed capture ends with an explicit
`... [capture trimmed: first N of M lines]` marker, so a truncated table is never
presented as if it were complete.

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
- Output for the nine commands that exist only on newer CE builds is absent, since
  this tenant runs `crt-20250613-3382`. They are recorded by name and tier only.
