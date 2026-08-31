"""
Product resolution — one ranked matcher shared by chat, voice, and visual audit.

Replaces three separate ad-hoc substring matchers that each picked a product by
"first thing that contains this word", which is how the assistant ended up
updating the wrong SKU.

The important behaviour here is that **ambiguity is a first-class outcome**.
When two products score within a hair of each other, the caller is told to ask
the user which one rather than silently guessing.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

try:  # optional: ~10x faster on large catalogs
    from rapidfuzz.fuzz import token_set_ratio as _rf_ratio  # type: ignore

    def _fuzzy(a: str, b: str) -> float:
        return _rf_ratio(a, b) / 100.0
except Exception:  # pragma: no cover - exercised only without rapidfuzz

    def _fuzzy(a: str, b: str) -> float:
        return SequenceMatcher(None, a, b).ratio()


# Words that describe the *action*, not the product.
COMMAND_WORDS = {
    "add", "added", "adding", "deduct", "deducted", "remove", "removed", "reduce",
    "reduced", "increase", "increased", "decrease", "restock", "restocked", "update",
    "updated", "set", "create", "make", "order", "reorder", "purchase", "po", "buy",
    "transfer", "move", "audit", "count", "check", "show", "tell", "give", "get",
    "find", "search", "how", "many", "much", "what", "whats", "which", "where", "is",
    "are", "the", "a", "an", "of", "for", "to", "from", "in", "on", "at", "with", "my",
    "our", "me", "please", "do", "does", "have", "has", "i", "we", "stock", "inventory",
    "units", "unit", "u", "pcs", "pieces", "piece", "qty", "quantity", "item", "items",
    "product", "products", "sku", "and", "it", "them", "this", "that", "there", "left",
    "available", "current", "currently", "now", "level", "levels", "damaged", "sold",
    "received", "receive", "new", "some", "all", "any", "please", "confirm", "yes",
}

_TOKEN_RE = re.compile(r"[a-z0-9]+")
_NUMERIC_RE = re.compile(r"^\d+$")

# Scoring
MIN_SCORE = 0.45          # below this a product is not a candidate at all
CONFIDENT_SCORE = 0.82    # above this we accept the top hit even if #2 is close
AMBIGUITY_MARGIN = 0.08   # top and runner-up within this -> ask the user
UBIQUITOUS_DF = 0.4       # a token in >40% of names carries no identifying power
# ...but only once there are enough products for document frequency to mean
# anything. In a two-product catalog every distinguishing word appears in 50% of
# names, and penalising those would make the resolver reject perfectly good
# matches for small businesses.
MIN_CATALOG_FOR_DF = 8


def normalize(text: str) -> str:
    return " ".join(_TOKEN_RE.findall((text or "").lower()))


def tokenize(text: str) -> List[str]:
    return _TOKEN_RE.findall((text or "").lower())


# Words that mark the number before or after them as a quantity rather than
# part of a product's name.
_QUANTITY_MARKERS = {
    "units", "unit", "pcs", "piece", "pieces", "qty", "quantity", "nos",
    "box", "boxes", "packs", "pack", "add", "deduct", "remove", "reduce",
    "increase", "restock", "received", "order", "reorder", "sold", "damaged",
    "by", "of",
}


def _is_quantity(tokens: List[str], index: int) -> bool:
    """Is the number at `index` a quantity, or part of the product's name?

    Stripping every number destroys names that contain one — "deduct 80 units
    of TEST 1" loses the 1 and then matches TEST2 better than TEST 1, because
    the only surviving token is the prefix they all share. A number counts as a
    quantity when a quantity word sits next to it.
    """
    before = tokens[index - 1] if index > 0 else ""
    after = tokens[index + 1] if index + 1 < len(tokens) else ""
    if after in _QUANTITY_MARKERS and after not in ("of", "by"):
        return True
    if before in _QUANTITY_MARKERS:
        return True
    # A bare number on its own is an answer to "how many?".
    return len(tokens) == 1


def strip_command_words(query: str, keep_numbers: bool = False) -> str:
    """Reduce 'add 50 units of fresh apples' to 'fresh apples'."""
    tokens = tokenize(query)
    kept = []
    for i, t in enumerate(tokens):
        if t in COMMAND_WORDS:
            continue
        if not keep_numbers and _NUMERIC_RE.match(t) and _is_quantity(tokens, i):
            continue
        kept.append(t)
    return " ".join(kept) if kept else " ".join(tokens)


def _tokens_match(a: str, b: str) -> bool:
    if a == b:
        return True
    if len(a) >= 4 and len(b) >= 4:
        return a.startswith(b) or b.startswith(a)
    return False


@dataclass
class Candidate:
    product: Any  # ProductFact
    score: float
    reason: str

    @property
    def name(self) -> str:
        return getattr(self.product, "name", "")

    @property
    def barcode(self) -> str:
        return getattr(self.product, "barcode", "")


@dataclass
class Resolution:
    status: str  # "resolved" | "ambiguous" | "not_found"
    candidates: List[Candidate]
    query: str

    @property
    def product(self) -> Optional[Any]:
        return self.candidates[0].product if self.candidates else None

    @property
    def confidence(self) -> float:
        return self.candidates[0].score if self.candidates else 0.0

    def options(self, limit: int = 4) -> List[Dict[str, Any]]:
        return [
            {
                "name": c.name,
                "barcode": c.barcode,
                "stock": getattr(c.product, "quantity", 0),
                "available": getattr(c.product, "available_qty", 0),
                "confidence": round(c.score, 3),
            }
            for c in self.candidates[:limit]
        ]

    def clarification(self, limit: int = 4) -> str:
        if self.status == "not_found":
            return (
                f"I couldn't find any product matching \"{self.query}\" in your catalog. "
                f"Try the exact product name or scan the barcode."
            )
        rows = "\n".join(
            f"| **{o['name']}** | `{o['barcode']}` | {o['stock']} |"
            for o in self.options(limit)
        )
        return (
            f"I found {len(self.candidates)} products matching \"{self.query}\". "
            f"Which one did you mean?\n\n"
            f"| Product | Barcode | Stock |\n| :--- | :--- | :--- |\n{rows}\n\n"
            f"Reply with the exact product name or its barcode."
        )


class ProductResolver:
    """Builds a small IDF index over a catalog and ranks products against a query."""

    def __init__(self, products: Sequence[Any]):
        self.products = list(products)
        self._name_tokens: List[List[str]] = []
        self._idf: Dict[str, float] = {}
        self._df: Dict[str, int] = {}
        self._build_index()

    def _build_index(self) -> None:
        total = max(1, len(self.products))
        for p in self.products:
            tokens = tokenize(getattr(p, "name", ""))
            self._name_tokens.append(tokens)
            for t in set(tokens):
                self._df[t] = self._df.get(t, 0) + 1
        for token, df in self._df.items():
            self._idf[token] = math.log((total + 1) / (df + 1)) + 1.0

    def _is_ubiquitous(self, token: str) -> bool:
        total = len(self.products)
        if total < MIN_CATALOG_FOR_DF:
            return False
        return (self._df.get(token, 0) / total) > UBIQUITOUS_DF

    # ------------------------------------------------------------------

    def resolve(self, query: str, limit: int = 5) -> Resolution:
        raw = (query or "").strip()
        if not raw or not self.products:
            return Resolution("not_found", [], raw)

        raw_tokens = tokenize(raw)

        # 1. Exact barcode or document id anywhere in the query — unambiguous.
        for p in self.products:
            barcode = str(getattr(p, "barcode", "") or "").strip().lower()
            pid = str(getattr(p, "id", "") or "").strip().lower()
            if barcode and barcode in raw_tokens:
                return Resolution("resolved", [Candidate(p, 1.0, "barcode")], raw)
            if pid and pid in raw_tokens and len(pid) > 6:
                return Resolution("resolved", [Candidate(p, 1.0, "product_id")], raw)

        cleaned = strip_command_words(raw)
        q_tokens = [t for t in tokenize(cleaned)]
        if not q_tokens:
            return Resolution("not_found", [], raw)
        q_set = set(q_tokens)
        norm_query = " ".join(q_tokens)

        # 2. Exact full-name match — but only when it identifies one product.
        # Catalogs really do carry several items with the same name, separable
        # only by barcode. An exact name match against duplicates identifies
        # nothing, so it must ask rather than pick the first.
        exact = [
            p
            for p in self.products
            if normalize(getattr(p, "name", "")) == norm_query
        ]
        if len(exact) == 1:
            return Resolution("resolved", [Candidate(exact[0], 1.0, "exact_name")], raw)
        if len(exact) > 1:
            return Resolution(
                "ambiguous",
                [Candidate(p, 1.0, "exact_name_duplicate") for p in exact[:limit]],
                raw,
            )

        # 3. Weighted scoring across the catalog.
        scored: List[Candidate] = []
        for p, name_tokens in zip(self.products, self._name_tokens):
            if not name_tokens:
                continue
            matched = [
                nt for nt in name_tokens if any(_tokens_match(nt, qt) for qt in q_set)
            ]
            if not matched:
                continue

            coverage = len(set(matched)) / len(set(name_tokens))
            precision = len(set(matched)) / len(q_set)
            fuzzy = _fuzzy(norm_query, normalize(getattr(p, "name", "")))
            score = 0.45 * coverage + 0.20 * precision + 0.35 * fuzzy

            # A match built only from words that nearly every product shares
            # ("basic", "standard", "box") identifies nothing.
            if all(self._is_ubiquitous(t) for t in matched):
                score *= 0.5

            # Whole product name present in the query is a strong signal.
            if normalize(getattr(p, "name", "")) in norm_query:
                score = max(score, 0.93)

            if score >= MIN_SCORE:
                scored.append(Candidate(p, round(score, 4), "fuzzy"))

        if not scored:
            return Resolution("not_found", [], raw)

        scored.sort(key=lambda c: (-c.score, getattr(c.product, "name", "")))
        top = scored[: max(limit, 2)]

        # A tie at the top identifies nothing, however confident the score is:
        # identically named products score identically by construction.
        tied_at_top = [c for c in top if abs(top[0].score - c.score) < 1e-9]
        if len(tied_at_top) > 1:
            return Resolution("ambiguous", tied_at_top[:limit], raw)

        if len(top) == 1 or top[0].score >= CONFIDENT_SCORE:
            return Resolution("resolved", top[:limit], raw)

        if (top[0].score - top[1].score) < AMBIGUITY_MARGIN:
            tied = [c for c in top if (top[0].score - c.score) < AMBIGUITY_MARGIN]
            return Resolution("ambiguous", tied[:limit], raw)

        return Resolution("resolved", top[:limit], raw)

    def search(self, query: str, limit: int = 10) -> List[Candidate]:
        """Ranked free-text search — no ambiguity semantics, just best matches."""
        res = self.resolve(query, limit=limit)
        return res.candidates


def resolve_product(query: str, facts: Any, limit: int = 5) -> Resolution:
    """Convenience wrapper: resolve `query` against an InventoryFacts snapshot."""
    return ProductResolver(getattr(facts, "products", []) or []).resolve(query, limit=limit)
