#!/usr/bin/env python3
"""Hermetic tests for scripts/sitecli_ssh_harvest.py.

Run via tests/test-sitecli-harvest.sh, which is what CI globs.

No network, no pty, no CE. Everything under test is a pure function that takes
bytes the appliance already produced and decides something about them.

The escape structure in the fixtures is copied from a real capture of the Site
CLI completion menu. It is not decorative: each detail is a way the parser can
be wrong.

  - Rows are separated by cursor-down (ESC[1B), never by newlines. Strip ANSI
    before splitting and all 82 rows concatenate into a single line.
  - The selected row uses different colour codes from the unselected ones, so a
    parser keyed on one colour pair silently sees a fraction of the menu.
  - Columns are space-padded to a fixed width, so name and description must be
    split on a run of spaces rather than a single one.
  - The prompt is redrawn inside the same stream and is not a menu row.
"""

import importlib.util
import json
import logging
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HARVEST_PATH = (
    Path(__file__).resolve().parent.parent / "scripts" / "sitecli_ssh_harvest.py"
)
HARVEST_SPEC = importlib.util.spec_from_file_location(
    "sitecli_ssh_harvest", HARVEST_PATH
)
if HARVEST_SPEC is None or HARVEST_SPEC.loader is None:
    raise ImportError(HARVEST_PATH)
h = importlib.util.module_from_spec(HARVEST_SPEC)
HARVEST_SPEC.loader.exec_module(h)

ESC = "\x1b"
UTC = timezone(timedelta())
DOWN = f"{ESC}[1B"
NAME_SELECTED = f"{ESC}[1;30;106m"
NAME_PLAIN = f"{ESC}[0;97;46m"
DESC_SELECTED = f"{ESC}[0;30;106m"
DESC_PLAIN = f"{ESC}[0;97;46m"


def row(name, desc, selected=False):
    """Render one menu row the way go-prompt draws it."""
    name_colour = NAME_SELECTED if selected else NAME_PLAIN
    desc_colour = DESC_SELECTED if selected else DESC_PLAIN
    return (
        f"{DOWN}{name_colour} {name:<38} {desc_colour} {desc:<110} "
        f"{ESC}[0;39;100m {ESC}[0;39;49m"
    )


def test_capture_timestamp_is_utc_rfc3339():
    """Format capture provenance as second-precision UTC RFC3339."""
    observed = datetime(2026, 8, 3, 16, 30, 6, tzinfo=UTC)
    assert h.capture_timestamp(observed) == "2026-08-03T16:30:06Z"


FIRST_PAGE = (
    f"{ESC}[12D{ESC}[?25l{ESC}[0;94;49m>>> {ESC}[0;39;49mexeccli {ESC}[J"
    + f"{ESC}D" * 6
    + f"{ESC}M" * 6
    + row("nh", "invoke argo nh command", selected=True)
    + row("dropstats", "dump argo dropstats")
    + row("vifdump-file-rm", "rm argo /tmp/*.pcap file")
    + row("vif", "invoke argo vif command")
    + row("vifdump-d", "Capture dropped packets on specified vif id or all vif")
    + row("rt", "invoke argo rt command")
)

# The window scrolled by one: five rows repeat, one is new. A harvester that
# does not de-duplicate reports 12 commands where there are 7.
SECOND_PAGE = (
    row("dropstats", "dump argo dropstats")
    + row("vifdump-file-rm", "rm argo /tmp/*.pcap file")
    + row("vif", "invoke argo vif command")
    + row("vifdump-d", "Capture dropped packets on specified vif id or all vif")
    + row("rt", "invoke argo rt command", selected=True)
    + row("flow-l", "dump argo flow info")
)


def refuses(name):
    """Report whether the guard rejects a command."""
    try:
        h.guard(name)
    except h.RefusedCommandError:
        return True
    return False


# --- menu parsing ------------------------------------------------------------


def test_extracts_every_row_on_a_page():
    """Extract every command row from one rendered completion page."""
    assert [n for n, _ in h.parse_menu(FIRST_PAGE)] == [
        "nh",
        "dropstats",
        "vifdump-file-rm",
        "vif",
        "vifdump-d",
        "rt",
    ]


def test_reads_the_selected_row_too():
    """Treat the differently coloured selected row as a command."""
    # The selected row carries different colour codes. It is a real command.
    assert ("nh", "invoke argo nh command") in h.parse_menu(FIRST_PAGE)


def test_keeps_descriptions_intact():
    """Keep the complete description after the padded name column."""
    rows = dict(h.parse_menu(FIRST_PAGE))
    assert rows["vifdump-d"] == "Capture dropped packets on specified vif id or all vif"


def test_ignores_the_prompt_redraw():
    """Exclude the interactive prompt redraw from parsed command names."""
    names = [n for n, _ in h.parse_menu(FIRST_PAGE)]
    assert "execcli" not in names
    assert ">>>" not in names


def test_a_description_containing_spaces_is_not_split_further():
    """Preserve ordinary spaces inside an appliance description."""
    rows = dict(h.parse_menu(row("files", "perform file operations on node")))
    assert rows["files"] == "perform file operations on node"


def test_empty_input_yields_nothing():
    """Return no commands for an empty terminal capture."""
    assert not h.parse_menu("")


# --- accumulation across a scrolling menu ------------------------------------


def test_overlapping_pages_deduplicate():
    """Deduplicate rows repeated across adjacent scrolling pages."""
    acc = h.MenuAccumulator()
    assert acc.absorb(FIRST_PAGE) == 6
    assert acc.absorb(SECOND_PAGE) == 1
    assert acc.count() == 7


def test_order_is_first_seen():
    """Retain the appliance's first-seen command order."""
    acc = h.MenuAccumulator()
    acc.absorb(FIRST_PAGE)
    acc.absorb(SECOND_PAGE)
    names = list(acc.commands)
    assert names[0] == "nh"
    assert names[-1] == "flow-l"


def test_a_repeated_page_adds_nothing():
    """Report zero additions when a page is absorbed twice."""
    acc = h.MenuAccumulator()
    acc.absorb(FIRST_PAGE)
    assert acc.absorb(FIRST_PAGE) == 0


# --- execution is default-denied ---------------------------------------------
#
# The guard that did not exist when `vifdump` was probed with no arguments on a
# registering node. A deny-list would not have helped: vifdump was on no list.
# Only an explicit allow-list refuses a command nobody thought about.


def test_a_known_read_only_command_is_allowed():
    """Allow commands explicitly classified as read-only."""
    assert h.may_execute("crictl-ps")
    assert h.may_execute("show-ip-bgp-summary")


def test_packet_capture_is_refused():
    """Refuse packet-capture commands that write files or change state."""
    for name in ("vifdump", "vifdump-d", "vifdump-stop", "vifdump-file-rm"):
        assert not h.may_execute(name), name


def test_mutating_commands_are_refused():
    """Refuse representative commands that mutate a live node."""
    for name in (
        "docker-prune",
        "systemctl-restart-vpm",
        "ip-link-set",
        "edit-etc-hosts",
        "get-auxilary-root-access-to-node",
        "kubelet-add-param",
        "factory-reset",
    ):
        assert not h.may_execute(name), name


def test_an_unknown_command_is_refused():
    """Default-deny commands absent from the explicit allow-list."""
    # The whole point: a command nobody has classified yet cannot be run.
    assert not h.may_execute("some-command-from-a-future-build")
    assert not h.may_execute("")


def test_current_build_read_only_commands_are_allowed():
    """Allow the current build's verified observational commands."""
    # These commands are on the rebuilt fleet. Four only read state, so the SSH
    # harness may capture them even though the debug API classifies the marker
    # checks in its privileged Exec tier.
    for name in (
        "iptables-lv",
        "marker-exists-NetworkManager",
        "marker-exists-crio",
        "marker-exists-kubelet",
    ):
        assert h.may_execute(name), name


def test_current_build_mutating_commands_stay_refused():
    """Keep current maintenance commands with side effects refused."""
    # Three of the current commands change the node. Enumeration records them; they are
    # documented by name and never run.
    #
    # `collect-database-stats` is here because its name is a lie: it runs a 15
    # second fio random-write benchmark against the etcd filesystem, laying out a
    # 250 MiB file. It was allow-listed on the strength of its name and its own
    # description ("collect database statistics"), run once on a disposable node,
    # and only the committed capture revealed the writes. The name-based tripwire
    # below cannot catch this, which is why the capture-scanning test exists.
    for name in (
        "collect-database-stats",
        "systemctl-restart-NetworkManager",
        "systemctl-start-crio-prune",
    ):
        assert not h.may_execute(name), name


def test_no_allow_listed_command_has_a_capture_showing_writes():
    """Reject an allow-listed command when its evidence shows writes."""
    # Evidence beats naming. A command's name and the appliance's own one-line
    # description can both be innocuous while the command writes to disk, so this
    # scans what the commands actually PRINTED and refuses to let any of them stay
    # on the read-only allow-list.
    #
    # This is the check that would have caught `collect-database-stats`.
    write_markers = (
        "randwrite",
        "rw=write",
        "fio-",
        "Laying out IO file",
        "disk performance test",
    )
    root = Path(__file__).resolve().parent.parent
    captures = sorted((root / "sitecli" / "captures").glob("sitecli-*.txt"))
    assert captures, "expected committed captures to scan"

    offenders = []
    for path in captures:
        name = path.name.removeprefix("sitecli-").removesuffix(".txt")
        if not h.may_execute(name):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        hits = [m for m in write_markers if m in text]
        if hits:
            offenders.append(f"{name} (capture shows {', '.join(hits)})")

    assert not offenders, (
        "allow-listed commands whose own output proves they write: "
        + "; ".join(offenders)
    )


def test_classification_mutating_list_agrees_with_the_allow_list():
    """Keep documentation safety classes aligned with executable policy."""
    # The documentation data and the harness must not disagree about which
    # commands are safe to run. Reading the JSON rather than restating its
    # contents is the point: adding a name to `_mutating` and to READ_ONLY at the
    # same time fails here instead of quietly permitting execution.
    root = Path(__file__).resolve().parent.parent
    data = json.loads(
        (root / "sitecli" / "command-classification.json").read_text(encoding="utf-8")
    )
    bucket = data["tiers"]["f5-software"]["node-maintenance"]
    mutating = bucket["_mutating"]

    assert mutating, "expected a non-empty _mutating list to test against"
    for name in mutating:
        assert name in bucket["commands"], f"{name} is not in the bucket it annotates"
        assert not h.may_execute(name), f"{name} is mutating but on the allow-list"

    # And the converse: every non-mutating command in the bucket IS runnable, so
    # the two files cannot drift into disagreeing about the safe subset either.
    for name in bucket["commands"]:
        if name not in mutating:
            assert h.may_execute(name), f"{name} is read-only but not on the allow-list"


def test_guard_raises_rather_than_returning_quietly():
    """Raise for a refused command and return normally for an allowed one."""
    assert refuses("vifdump")
    assert not refuses("crictl-ps")


def test_allow_list_contains_no_mutating_verb():
    """Trip on obvious mutating verbs added to the read-only allow-list."""
    # A cheap tripwire for future edits to the allow-list.
    forbidden = ("restart", "prune", "edit-", "-set", "add-param", "remove", "reset")
    for name in h.READ_ONLY:
        assert not any(word in name for word in forbidden), (
            f"{name} looks mutating but is on the read-only allow-list"
        )


# --- process teardown is bounded -------------------------------------------
#
# These use a real child on a real pty, because the bug they exist to catch was
# invisible to pure-function tests. close() used to let ExitStack unwind
# Popen.__exit__, which calls wait() with no timeout; a child that ignores
# SIGTERM then hangs the caller forever. A completed harvest was lost that way,
# since the catalog is written after close() returns. No network, no CE — just a
# process that refuses to die politely.


def test_close_returns_promptly_for_a_cooperative_child():
    """Reap a cooperative pseudo-terminal child without delay."""
    p = h.PtyProcess(["sleep", "60"])
    started = time.monotonic()
    p.close()
    assert time.monotonic() - started < 5, (
        "close() should not linger on a child that dies"
    )
    assert p.proc.poll() is not None, "child must be reaped"


def test_close_kills_a_child_that_ignores_sigterm():
    """Escalate to SIGKILL within a bound when SIGTERM is ignored."""
    # sh -c "trap '' TERM; sleep 60" does NOT work: sh exec's the final command,
    # replacing itself and discarding the trap, so the child dies on SIGTERM and
    # the SIGKILL path is never exercised. Install the handler in the process that
    # actually sleeps.
    #
    # The child must announce readiness. Closing immediately races interpreter
    # startup: SIGTERM arriving before the handler is installed kills the child
    # under the default disposition, and the SIGKILL path is never reached.
    child = (
        "import signal, sys, time; "
        "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
        "sys.stdout.write('ARMED\\n'); sys.stdout.flush(); "
        "time.sleep(60)"
    )
    p = h.PtyProcess([sys.executable, "-u", "-c", child])
    deadline = time.monotonic() + 10
    armed = ""
    while "ARMED" not in armed and time.monotonic() < deadline:
        armed += os.read(p.fd, 4096).decode("utf-8", "replace")
    assert "ARMED" in armed, "child never installed its SIGTERM handler"
    started = time.monotonic()
    p.close()
    elapsed = time.monotonic() - started
    assert p.proc.poll() is not None, "close() must reap even a SIGTERM-proof child"
    assert elapsed < 2 * h.PtyProcess.TERMINATE_GRACE + 2, (
        f"close() took {elapsed:.1f}s; teardown must stay bounded"
    )
    assert p.proc.returncode in (-signal.SIGKILL, signal.SIGKILL, 137), (
        f"expected SIGKILL, got returncode {p.proc.returncode}"
    )


def test_close_is_idempotent():
    """Allow repeated cleanup of the same pseudo-terminal process."""
    p = h.PtyProcess(["sleep", "60"])
    p.close()
    p.close()  # must not raise on an already-closed pty or a reaped child


# --- ssh argv ---------------------------------------------------------------


def test_ssh_argv_omits_proxy_command_when_no_jump_host():
    """Build a direct SSH command when no jump host is supplied."""
    argv = h.ssh_argv("10.0.3.7", "", "key-path-not-read")
    assert not any(a.startswith("ProxyCommand") for a in argv)
    assert argv[-1] == "admin@10.0.3.7"


def test_ssh_argv_propagates_trust_options_to_the_jump_leg():
    """Apply isolated host trust and key settings to both SSH legs."""
    argv = h.ssh_argv(
        "10.0.3.7",
        "azureuser@1.2.3.4",
        "key-path-not-read",
        user="admin",
        known_hosts="isolated-known-hosts",
    )
    proxy = next(a for a in argv if a.startswith("ProxyCommand="))
    assert "azureuser@1.2.3.4" in proxy
    assert "UserKnownHostsFile=isolated-known-hosts" in proxy
    assert "StrictHostKeyChecking=accept-new" in proxy
    assert "UserKnownHostsFile=isolated-known-hosts" in argv
    assert "BatchMode=yes" in argv
    assert argv[-1] == "admin@10.0.3.7"


# --- command output is trimmed of Site CLI chrome ---------------------------
#
# A captured command carries two pieces of interface with it: the prompt line
# echoing what was typed, and the completion menu the CLI repaints afterwards.
# Committing those verbatim puts `>>> execcli vegactl-...` and the whole
# six-entry top-level menu into the documentation as though the command had
# printed them.

MENU_REPAINT = (
    ">>>  configure                   Initial configuration of the node"
    "                configure-generic-hardware  Configure Hardware that isn't"
    " certified by F5XC.                configure-network           Initial"
    " configuration of the network"
)


def test_trim_drops_the_prompt_echo():
    """Remove the Site CLI prompt and echoed command from evidence."""
    raw = ">>> execcli vegactl-introspect-show-election\nrole: Master\n"
    assert h.trim_command_output(raw) == "role: Master"


def test_trim_drops_a_trailing_menu_repaint():
    """Remove the completion menu repainted after command output."""
    raw = f">>> execcli envoy-listeners\nlistener-1:80\n{MENU_REPAINT}\n"
    assert h.trim_command_output(raw) == "listener-1:80"


def test_trim_keeps_interior_content_and_blank_lines():
    """Preserve output content and meaningful interior blank lines."""
    raw = ">>> execcli x\nfirst\n\nsecond\n>>> \n"
    assert h.trim_command_output(raw) == "first\n\nsecond"


def test_trim_keeps_output_that_merely_mentions_the_prompt_string():
    """Keep real output that contains but does not begin with a prompt."""
    # A line containing >>> but not starting the line is real output.
    raw = ">>> execcli x\nusage: foo >>> bar\n"
    assert h.trim_command_output(raw) == "usage: foo >>> bar"


def test_trim_of_empty_or_prompt_only_output_is_empty():
    """Normalize empty and prompt-only captures to an empty string."""
    assert h.trim_command_output("") == ""
    assert h.trim_command_output(">>> execcli x\n>>> \n") == ""


#: Failures a test here can plausibly raise other than AssertionError. Enumerated
#: rather than catching Exception: a test written before the function it exercises
#: raises AttributeError, and that must be reported as one failing test rather
#: than aborting the remaining tests. Anything outside this set is unexpected and
#: is deliberately left to propagate — the run then ends with a traceback and a
#: non-zero exit, which is loud, rather than being folded into a tidy report.
EXPECTED_TEST_FAILURES = (
    AttributeError,
    IndexError,
    KeyError,
    OSError,
    TypeError,
    ValueError,
    subprocess.SubprocessError,
)


def run_one(fn):
    """Run one test and return its failure message, or None if it passed."""
    try:
        fn()
    except AssertionError as exc:
        return str(exc) or "assertion failed"
    except EXPECTED_TEST_FAILURES as exc:
        return f"{type(exc).__name__}: {exc}"
    return None


def main():
    """Run every test_* in this module and report like the shell suites do."""
    logging.basicConfig(format="%(message)s", level=logging.INFO, stream=sys.stdout)
    log = logging.getLogger("sitecli-harvest")
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        failure = run_one(fn)
        if failure is None:
            log.info("[OK] %s", name)
        else:
            log.info("[FAIL] %s - %s", name, failure)
            failures += 1
    log.info("sitecli-harvest tests %s", "FAILED" if failures else "passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
