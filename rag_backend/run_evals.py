#!/usr/bin/env python3
"""Grade the agent against the golden set.

    venv/bin/python run_evals.py                 # everything, text report
    venv/bin/python run_evals.py --suite safety  # one suite
    venv/bin/python run_evals.py -v              # show passing checks too
    venv/bin/python run_evals.py --json out.json # machine-readable, for CI

Exits non-zero when a case fails or a gate is missed, so it drops straight into
a pipeline next to the unit tests. Runs offline and free by default: the read
path answers from the fact layer, and the write path replays a scripted model.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("OFFLINE_MODE", "1")

from evals.report import summarise, to_json, to_text  # noqa: E402
from evals.runner import run_all  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", action="append", help="run only this suite (repeatable)")
    parser.add_argument("--json", dest="json_path", help="write the full report here")
    parser.add_argument("-v", "--verbose", action="store_true", help="show passing checks")
    parser.add_argument(
        "--min-pass-rate",
        type=float,
        default=100.0,
        help="fail below this pass rate (default: 100)",
    )
    parser.add_argument(
        "--min-deterministic-coverage",
        type=float,
        default=0.0,
        help=(
            "fail if fewer than this percent of cases answered with no model "
            "call. The cost regression gate: set it to the current coverage in "
            "CI and a change that routes a free question through the agent has "
            "to justify itself."
        ),
    )
    args = parser.parse_args()

    results = asyncio.run(run_all(args.suite))
    print(to_text(results, verbose=args.verbose))

    if args.json_path:
        with open(args.json_path, "w") as fh:
            fh.write(to_json(results))
        print(f"\nreport written to {args.json_path}")

    s = summarise(results)
    failures = []
    if s["pass_rate_pct"] < args.min_pass_rate:
        failures.append(
            f"pass rate {s['pass_rate_pct']}% is below the {args.min_pass_rate}% gate"
        )
    if s["deterministic_coverage_pct"] < args.min_deterministic_coverage:
        failures.append(
            f"deterministic coverage {s['deterministic_coverage_pct']}% is below "
            f"the {args.min_deterministic_coverage}% gate — something that used "
            f"to be free now calls the model"
        )

    if failures:
        print("\nGATE FAILED:")
        for f in failures:
            print(f"  - {f}")
        return 1

    print("\nAll gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
