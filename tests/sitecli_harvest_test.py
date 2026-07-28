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

import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import sitecli_ssh_harvest as h

ESC = "\x1b"
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
    assert [n for n, _ in h.parse_menu(FIRST_PAGE)] == [
        "nh",
        "dropstats",
        "vifdump-file-rm",
        "vif",
        "vifdump-d",
        "rt",
    ]


def test_reads_the_selected_row_too():
    # The selected row carries different colour codes. It is a real command.
    assert ("nh", "invoke argo nh command") in h.parse_menu(FIRST_PAGE)


def test_keeps_descriptions_intact():
    rows = dict(h.parse_menu(FIRST_PAGE))
    assert rows["vifdump-d"] == "Capture dropped packets on specified vif id or all vif"


def test_ignores_the_prompt_redraw():
    names = [n for n, _ in h.parse_menu(FIRST_PAGE)]
    assert "execcli" not in names
    assert ">>>" not in names


def test_a_description_containing_spaces_is_not_split_further():
    rows = dict(h.parse_menu(row("files", "perform file operations on node")))
    assert rows["files"] == "perform file operations on node"


def test_empty_input_yields_nothing():
    assert not h.parse_menu("")


# --- accumulation across a scrolling menu ------------------------------------


def test_overlapping_pages_deduplicate():
    acc = h.MenuAccumulator()
    assert acc.absorb(FIRST_PAGE) == 6
    assert acc.absorb(SECOND_PAGE) == 1
    assert len(acc.commands) == 7


def test_order_is_first_seen():
    acc = h.MenuAccumulator()
    acc.absorb(FIRST_PAGE)
    acc.absorb(SECOND_PAGE)
    names = list(acc.commands)
    assert names[0] == "nh"
    assert names[-1] == "flow-l"


def test_a_repeated_page_adds_nothing():
    acc = h.MenuAccumulator()
    acc.absorb(FIRST_PAGE)
    assert acc.absorb(FIRST_PAGE) == 0


# --- execution is default-denied ---------------------------------------------
#
# The guard that did not exist when `vifdump` was probed with no arguments on a
# registering node. A deny-list would not have helped: vifdump was on no list.
# Only an explicit allow-list refuses a command nobody thought about.


def test_a_known_read_only_command_is_allowed():
    assert h.may_execute("crictl-ps")
    assert h.may_execute("show-ip-bgp-summary")


def test_packet_capture_is_refused():
    for name in ("vifdump", "vifdump-d", "vifdump-stop", "vifdump-file-rm"):
        assert not h.may_execute(name), name


def test_mutating_commands_are_refused():
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
    # The whole point: a command nobody has classified yet cannot be run.
    assert not h.may_execute("some-command-from-a-future-build")
    assert not h.may_execute("")


def test_guard_raises_rather_than_returning_quietly():
    assert refuses("vifdump")
    assert not refuses("crictl-ps")


def test_allow_list_contains_no_mutating_verb():
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
    p = h.PtyProcess(["sleep", "60"])
    started = time.monotonic()
    p.close()
    assert time.monotonic() - started < 5, (
        "close() should not linger on a child that dies"
    )
    assert p.proc.poll() is not None, "child must be reaped"


def test_close_kills_a_child_that_ignores_sigterm():
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
    p = h.PtyProcess(["sleep", "60"])
    p.close()
    p.close()  # must not raise on an already-closed pty or a reaped child


# --- ssh argv ---------------------------------------------------------------


def test_ssh_argv_omits_proxyjump_when_no_jump_host():
    argv = h.ssh_argv("10.0.3.7", "", "key-path-not-read")
    assert not any(a.startswith("ProxyJump") for a in argv)
    assert argv[-1] == "admin@10.0.3.7"


def test_ssh_argv_includes_proxyjump_and_user():
    argv = h.ssh_argv(
        "10.0.3.7", "azureuser@1.2.3.4", "key-path-not-read", user="admin"
    )
    assert "ProxyJump=azureuser@1.2.3.4" in argv
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
    raw = ">>> execcli vegactl-introspect-show-election\nrole: Master\n"
    assert h.trim_command_output(raw) == "role: Master"


def test_trim_drops_a_trailing_menu_repaint():
    raw = f">>> execcli envoy-listeners\nlistener-1:80\n{MENU_REPAINT}\n"
    assert h.trim_command_output(raw) == "listener-1:80"


def test_trim_keeps_interior_content_and_blank_lines():
    raw = ">>> execcli x\nfirst\n\nsecond\n>>> \n"
    assert h.trim_command_output(raw) == "first\n\nsecond"


def test_trim_keeps_output_that_merely_mentions_the_prompt_string():
    # A line containing >>> but not starting the line is real output.
    raw = ">>> execcli x\nusage: foo >>> bar\n"
    assert h.trim_command_output(raw) == "usage: foo >>> bar"


def test_trim_of_empty_or_prompt_only_output_is_empty():
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
