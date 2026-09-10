#!/usr/bin/env python3
"""Run the backend suite, both conventions, one exit code.

This repo grew two kinds of test. Most are scripts: they assert at import time
and call ``sys.exit(1)``, which is a perfectly good way to write a test and a
terrible one to discover — ``pytest`` collects nothing from them and reports
success. A handful are ordinary pytest modules. Before this, running "the
tests" meant knowing which was which.

    venv/bin/python run_tests.py           # everything
    venv/bin/python run_tests.py --list    # what would run, and how
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).parent
PYTEST_MARKER = re.compile(r"^(def test_|async def test_|class Test)", re.MULTILINE)

# Needs a live endpoint or a running server, so it is not part of the default
# run. Named rather than pattern-matched, so adding a test never silently opts
# it out.
EXCLUDED = {"test_api_server.py"}


def classify(path: Path) -> str:
    return "pytest" if PYTEST_MARKER.search(path.read_text()) else "script"


def discover():
    for path in sorted(ROOT.glob("test_*.py")):
        if path.name in EXCLUDED:
            continue
        yield path, classify(path)


def _child_env() -> dict:
    """The environment a test file gets.

    ``OFFLINE_MODE`` is stripped rather than passed through, and that is not
    tidiness. ``Principal.has`` short-circuits to ``True`` when it is set, so a
    developer who exported it in their shell — or a runner that helpfully set it
    "because the tests are offline" — turns every permission assertion in
    ``test_auth_permissions.py`` into a tautology and gets five green ticks for
    an agent that would let a viewer write. The files that genuinely need the
    offline store set it themselves, at import, via ``testkit``.
    """
    env = dict(os.environ)
    env.pop("OFFLINE_MODE", None)
    return env


def run(path: Path, kind: str, python: str) -> tuple:
    cmd = (
        [python, "-m", "pytest", str(path), "-q"]
        if kind == "pytest"
        else [python, str(path)]
    )
    started = time.perf_counter()
    proc = subprocess.run(
        cmd, cwd=ROOT, capture_output=True, text=True, env=_child_env()
    )
    return proc.returncode, (time.perf_counter() - started), proc.stdout + proc.stderr


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="show what would run")
    parser.add_argument("-v", "--verbose", action="store_true", help="show all output")
    args = parser.parse_args()

    python = sys.executable
    tests = list(discover())

    if args.list:
        for path, kind in tests:
            print(f"  {kind:7}  {path.name}")
        print(f"\n{len(tests)} test file(s)")
        return 0

    print(f"Running {len(tests)} test file(s)\n")

    failed = []
    for path, kind in tests:
        code, secs, output = run(path, kind, python)
        mark = "pass" if code == 0 else "FAIL"
        print(f"  {mark}  {path.name:34} [{kind}, {secs:.1f}s]")
        if code != 0:
            failed.append(path.name)
            print("\n".join("        " + l for l in output.strip().splitlines()[-25:]))
        elif args.verbose:
            print("\n".join("        " + l for l in output.strip().splitlines()[-5:]))

    print("\n" + "=" * 64)
    if failed:
        print(f"{len(failed)} file(s) FAILED: {', '.join(failed)}")
        return 1
    print(f"All {len(tests)} test file(s) passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
