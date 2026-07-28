#!/usr/bin/env bash
# Runs the Python unit tests for scripts/sitecli_ssh_harvest.py.
#
# This wrapper exists because the shared Shell Unit Tests job globs
# `tests/test-*.sh` and nothing else, so a bare .py test would never run in CI.
# Everything it drives is hermetic: no network, no pty, no Customer Edge.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec python3 "${REPO_ROOT}/tests/test-sitecli-harvest.py"
