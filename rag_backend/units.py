"""Packs: "2 boxes" of a ten-to-a-box product is 20 pieces.

The app stores every quantity in a product's base unit. A product can also
have a pack — "1 box = 10 pcs", set on the product or by a rule in Settings ›
Unit conversions — and people count in packs. Everything the assistant writes
has to be in base units, so a number said in packs is multiplied here, once,
before anything is previewed or written.

The rules mirror the app's `resolveUnitConversion`
(`lib/services/unit_conversion_planner.dart`); the two have to agree, or a
product the assistant creates would follow a different conversion from the
one Settings shows.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional

_COUNT_RE = re.compile(r"\b(\d{1,6})\s*([a-z]+)\b")


def same_label(a: Any, b: Any) -> bool:
    """Hand-typed labels — units, brands, sizes — compared as people mean them."""
    return str(a or "").strip().lower() == str(b or "").strip().lower()


def names_unit(word: str, unit: str) -> bool:
    """Whether `word` is `unit` said out loud: "box", "boxes", "Box"."""
    w = str(word or "").strip().lower()
    u = str(unit or "").strip().lower()
    return bool(u) and w in {u, u + "s", u + "es"}


def packs_said(text: str, pack_unit: str) -> Optional[int]:
    """How many packs `text` names — 2 for "add 2 boxes of tiles" — or None."""
    if not pack_unit:
        return None
    for number, word in _COUNT_RE.findall((text or "").lower()):
        if names_unit(word, pack_unit):
            return int(number)
    return None


def breakdown(quantity: int, base_unit: str, pack_unit: str, units_per_pack: int) -> str:
    """'5 box 3 pcs' for 53 at ten to a box; the app's formatQuantityWithUnits."""
    quantity = max(0, int(quantity))
    if units_per_pack <= 1 or not pack_unit:
        return f"{quantity} {base_unit}"
    packs, pieces = divmod(quantity, units_per_pack)
    if packs == 0:
        return f"{pieces} {base_unit}"
    if pieces == 0:
        return f"{packs} {pack_unit}"
    return f"{packs} {pack_unit} {pieces} {base_unit}"


# --- Settings › Unit conversions ---------------------------------------------


def rules_from_settings(raw: Any) -> List[Dict[str, Any]]:
    """`settings.unitConversions`, minus anything a save could never produce."""
    rules: List[Dict[str, Any]] = []
    if not isinstance(raw, list):
        return rules
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        try:
            per_pack = int(entry.get("unitsPerPack") or 0)
        except (TypeError, ValueError):
            continue
        pack = str(entry.get("packUnit") or "").strip()
        base = str(entry.get("baseUnit") or "").strip()
        if not entry.get("id") or per_pack < 2 or not pack or not base:
            continue
        if same_label(pack, base):
            continue
        rules.append(entry)
    return rules


def _pinned(rule: Dict[str, Any]) -> Dict[str, bool]:
    return {
        "category": bool(str(rule.get("categoryId") or "")),
        "company": bool(str(rule.get("company") or "").strip()),
        "size": bool(str(rule.get("size") or "").strip()),
    }


def _matches(rule: Dict[str, Any], category_id: str, company: str, size: str) -> bool:
    if rule.get("categoryId") and rule["categoryId"] != category_id:
        return False
    if str(rule.get("company") or "").strip() and not same_label(rule["company"], company):
        return False
    if str(rule.get("size") or "").strip() and not same_label(rule["size"], size):
        return False
    return True


def _rank(rule: Dict[str, Any]) -> tuple:
    pinned = _pinned(rule)
    specificity = sum(pinned.values())
    # Between equally specific rules: sub-category, then brand, then category.
    precedence = 4 * pinned["size"] + 2 * pinned["company"] + pinned["category"]
    return (specificity, precedence)


def resolve_rule(
    rules: Iterable[Dict[str, Any]],
    category_id: str = "",
    company: str = "",
    size: str = "",
) -> Optional[Dict[str, Any]]:
    """The rule a product with these attributes follows, or None.

    The most specific match wins; Settings refuses two rules with the same
    scope, so the ranking always has one answer.
    """
    best: Optional[Dict[str, Any]] = None
    for rule in rules:
        if not _matches(rule, category_id or "", company or "", size or ""):
            continue
        if best is None or _rank(rule) > _rank(best):
            best = rule
    return best


def units_for_new_product(
    rules: Iterable[Dict[str, Any]],
    unit: str,
    category_id: str = "",
    company: str = "",
    size: str = "",
) -> Dict[str, Any]:
    """The unit fields a new product should be created with.

    A new product holds no stock yet, so it takes its rule's units outright —
    unless the person named a unit the rule is not counted in ("kg" under
    "1 box = 10 pcs"), which is theirs to keep.
    """
    base = (unit or "").strip() or "pcs"
    plain = {"unit": base, "baseUnit": base, "packUnit": "box", "unitsPerPack": 1}
    rule = resolve_rule(rules, category_id, company, size)
    if rule is None:
        return plain
    if unit and not same_label(unit, rule["baseUnit"]):
        return plain
    return {
        "unit": rule["baseUnit"],
        "baseUnit": rule["baseUnit"],
        "packUnit": rule["packUnit"],
        "unitsPerPack": int(rule["unitsPerPack"]),
    }
