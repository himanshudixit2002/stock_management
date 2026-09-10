#!/usr/bin/env python3
"""Write the API's OpenAPI schema to a file that lives in the repo.

The schema is committed rather than generated on demand, and CI regenerates it
and fails on any difference. That turns a silent break into a visible one: the
Flutter client parses these responses by hand, so a field renamed in a Pydantic
model is a runtime null on someone's phone and nothing anywhere says so. With
the schema in the diff, renaming a field means touching a file called
``openapi.json``, in the same commit, where a reviewer sees it.

    venv/bin/python tools/export_openapi.py            # write it
    venv/bin/python tools/export_openapi.py --check    # fail if stale
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# Importing the app must not require credentials or reach Firestore.
os.environ.setdefault("OFFLINE_MODE", "1")

DEFAULT_OUT = ROOT / "openapi.json"


def build() -> dict:
    import main

    schema = main.app.openapi()
    # `sort_keys` on dump handles ordering, but the version string moves with
    # the FastAPI release and would churn the diff for no reason.
    schema.setdefault("info", {})["version"] = os.environ.get("API_VERSION", "1.0.0")
    return schema


def main_cli() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if the file on disk is not what the app produces",
    )
    args = parser.parse_args()

    rendered = json.dumps(build(), indent=2, sort_keys=True) + "\n"
    out = Path(args.out)

    if args.check:
        if not out.exists():
            print(f"{out} does not exist — run this without --check to create it.")
            return 1
        if out.read_text() != rendered:
            print(
                f"{out.name} is out of date with the app.\n"
                "Regenerate it and commit the result:\n"
                "    venv/bin/python tools/export_openapi.py"
            )
            return 1
        print(f"{out.name} matches the app.")
        return 0

    out.write_text(rendered)
    paths = len(json.loads(rendered).get("paths", {}))
    print(f"wrote {out} ({paths} paths)")
    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
