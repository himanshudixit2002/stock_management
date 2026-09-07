"""Check model-authored answers against the facts that produced them.

The assistant has been observed stating things its own data contradicts — most
memorably replying "Product with barcode X not found" for a barcode it had
listed moments earlier. A wrong number delivered confidently is worse than a
hedge, because nothing downstream questions it.

This is a last line of defence, not a replacement for grounding: it catches
claims that can be mechanically checked and leaves prose alone. Deterministic
answers skip it entirely — they are correct by construction.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, List, Optional, Tuple

# "**Cannula Basic** ... 94 units" / "Cannula Basic has 94 units"
_STOCK_CLAIM = re.compile(
    r"\*\*(?P<name>[^*\n]{3,60})\*\*[^.\n|]{0,40}?\b(?P<qty>\d[\d,]*)\s*(?:units?|pcs|in stock)",
    re.IGNORECASE,
)
# Names that are obviously stand-ins rather than catalog entries. The model
# reaches for these when it is asked to lay out a table it has no rows for —
# and a table of "SKU 1 / SKU 2" reads, to someone skimming, exactly like real
# inventory.
#
# Deliberately narrow. An earlier, looser version matched the plain word
# "SKUs", and "the item I would reorder first" — so it threw away good answers
# and replaced them with a stock summary. A missed placeholder is a bad
# sentence; a false positive destroys a correct answer, which is worse.
_PLACEHOLDER = re.compile(
    # "SKU 1", "Product #2", "Item-3" — a bare noun plus a number, and the
    # noun must not be plural ("200 SKUs" is a real count, not a name).
    r"(?i:\b(?:sku|product|item|article)\s*[-_#]?\s*\d{1,3}\b(?!\s*(?:%|units?|pcs)))"
    # "Product A" / "Item B" — capitalised single letter only, so "the item a
    # customer wants" does not match. This one alternative is case-sensitive.
    r"|\b(?:Product|Item|SKU|Article)\s+[A-Z]\b"
    # Explicit fill-in-the-blank markers.
    r"|(?i:<\s*(?:product|item|sku|name)[^>]{0,20}>)"
    r"|(?i:\[(?:product|item|sku)[\s_]?(?:name|here)?[^\]]{0,10}\])"
    r"|(?i:\bexample\s+(?:product|item|sku)\b)"
    r"|(?i:\byour\s+(?:product|item)\s+here\b)"
    r"|(?i:\blorem\b)",
)

# Forms that are unambiguous on their own. Anything else has to appear at
# least twice before it is treated as a fabricated listing rather than a turn
# of phrase.
_DEFINITE_PLACEHOLDER = re.compile(
    r"\bexample\s+(?:product|item|sku)\b"
    r"|<\s*(?:product|item|sku|name)[^>]{0,20}>"
    r"|\[(?:product|item|sku)[\s_]?(?:name|here)?[^\]]{0,10}\]"
    r"|\byour\s+(?:product|item)\s+here\b"
    r"|\blorem\b",
    re.IGNORECASE,
)


_NOT_FOUND = re.compile(
    r"(?:product|item|barcode)\s+(?:with\s+barcode\s+)?[\"'`]?(?P<ref>[\w .()\-/]{3,40})[\"'`]?\s+"
    r"(?:was\s+)?not\s+found",
    re.IGNORECASE,
)


@dataclass
class Issue:
    kind: str          # "wrong_quantity" | "false_not_found" | "placeholder"
    detail: str
    claimed: Optional[str] = None
    actual: Optional[str] = None


def _int(text: str) -> Optional[int]:
    try:
        return int(text.replace(",", ""))
    except ValueError:
        return None


def check_answer(answer: str, facts: Any) -> Tuple[str, List[Issue]]:
    """Return the answer with checkable errors corrected, plus what was found.

    Only claims that can be settled against the snapshot are touched. Anything
    ambiguous is left exactly as written — silently rewriting prose would be a
    worse failure than the one being prevented.
    """
    if not answer or facts is None:
        return answer, []

    issues: List[Issue] = []
    corrected = answer

    by_name = {}
    for p in getattr(facts, "products", []) or []:
        by_name.setdefault(p.name.strip().lower(), []).append(p)

    # 1. A stock figure attached to a named product must match the snapshot.
    for match in list(_STOCK_CLAIM.finditer(answer)):
        name = match.group("name").strip().lower()
        claimed = _int(match.group("qty"))
        candidates = by_name.get(name)
        if claimed is None or not candidates:
            continue
        if len(candidates) > 1:
            # Duplicate names cannot be resolved from the text alone.
            continue
        actual = candidates[0].quantity
        if claimed != actual:
            issues.append(
                Issue("wrong_quantity", f"{candidates[0].name}", str(claimed), str(actual))
            )
            start, end = match.span("qty")
            corrected = corrected.replace(
                match.group(0),
                match.group(0)[: start - match.start()]
                + str(actual)
                + match.group(0)[end - match.start() :],
                1,
            )

    # 2. Placeholder product names, which are never an answer.
    found = []
    for match in _PLACEHOLDER.finditer(answer):
        text = match.group(0).strip()
        # A real product may legitimately be called "Item 5" — only flag a name
        # the catalog does not actually contain.
        if text.lower() in by_name:
            continue
        found.append(text)
    # One "Product A" in a sentence is a turn of phrase; a table of them is a
    # fabricated listing. Explicit fill-in markers count on their own.
    if len(found) > 1 or (found and _DEFINITE_PLACEHOLDER.search(answer)):
        issues.extend(Issue("placeholder", t) for t in found)

    # 3. "not found" about something that is in the catalog.
    for match in _NOT_FOUND.finditer(answer):
        ref = match.group("ref").strip()
        known = getattr(facts, "lookup", lambda _: None)(ref) or (
            by_name.get(ref.lower(), [None])[0]
        )
        if known is not None:
            issues.append(
                Issue("false_not_found", ref, "not found", f"{known.name} ({known.quantity} units)")
            )

    return corrected, issues


def describe(issues: List[Issue]) -> str:
    return "; ".join(
        f"{i.kind}: {i.detail} claimed {i.claimed}, actual {i.actual}" for i in issues
    )
