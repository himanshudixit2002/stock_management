#!/usr/bin/env python3
"""Render docs/architecture.html to a PDF with a running footer.

Chrome does the typesetting, because its print CSS support is better than
anything that would fit in this script. It cannot, however, be told to print a
footer that is not the source file:// path, so page numbers are drawn separately
and merged over the rendered pages.

    python docs/build_pdf.py

Needs pypdf and reportlab (pip install pypdf reportlab), and a Chrome or
Chromium binary — set CHROME to point at one if it is somewhere unusual.
"""

from __future__ import annotations

import io
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "architecture.html"
OUTPUT = ROOT / "SmartShelfKart-Architecture.pdf"
FOOTER = "SmartShelfKart — System architecture and technical reference"

CANDIDATES = [
    os.environ.get("CHROME", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
    shutil.which("chromium-browser") or "",
]


def find_chrome() -> str:
    for path in CANDIDATES:
        if path and Path(path).exists():
            return path
    sys.exit(
        "No Chrome or Chromium binary found. Set CHROME to one, e.g.\n"
        "    CHROME=/path/to/chrome python docs/build_pdf.py"
    )


def render(chrome: str, target: Path) -> None:
    subprocess.run(
        [
            chrome,
            "--headless",
            "--disable-gpu",
            "--no-sandbox",
            "--no-pdf-header-footer",
            f"--print-to-pdf={target}",
            # Web fonts and layout need a moment to settle; without this the
            # first render occasionally lands before the CSS is applied.
            "--virtual-time-budget=8000",
            SOURCE.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def stamp(body: Path, out: Path) -> int:
    from pypdf import PdfReader, PdfWriter
    from reportlab.lib.colors import HexColor
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    reader = PdfReader(str(body))
    writer = PdfWriter()
    total = len(reader.pages)

    for index, page in enumerate(reader.pages):
        if index:  # the cover carries no furniture
            buf = io.BytesIO()
            c = canvas.Canvas(buf, pagesize=A4)
            width, _ = A4
            c.setStrokeColor(HexColor("#d8dde2"))
            c.setLineWidth(0.4)
            c.line(51, 40, width - 51, 40)
            c.setFont("Times-Roman", 7.6)
            c.setFillColor(HexColor("#8a8a8a"))
            c.drawString(51, 30, FOOTER)
            c.drawRightString(width - 51, 30, f"{index + 1} / {total}")
            c.save()
            buf.seek(0)
            page.merge_page(PdfReader(buf).pages[0])
        writer.add_page(page)

    writer.add_metadata(
        {
            "/Title": "SmartShelfKart — System Architecture and Technical Reference",
            "/Subject": (
                "Data model, authorization, domain modules, inventory mathematics, "
                "the assistant service, and the delivery pipeline"
            ),
            "/Creator": "Engineering reference, revision 1",
        }
    )
    with open(out, "wb") as fh:
        writer.write(fh)
    return total


def main() -> int:
    if not SOURCE.exists():
        sys.exit(f"{SOURCE} is missing.")
    chrome = find_chrome()
    with tempfile.TemporaryDirectory() as tmp:
        body = Path(tmp) / "body.pdf"
        render(chrome, body)
        pages = stamp(body, OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({pages} pages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
