"""Graders. Each one answers a single yes/no question about a finished turn.

Two rules shaped this file.

*Structure over prose.* Where the pipeline already records a fact about what it
did — the intent it routed to, the rows it returned, whether a write actually
landed — the scorer reads that record instead of searching the English for a
hint of it. String matching is reserved for the cases where the wording genuinely
is the contract.

*A wrong number must fail, a reworded sentence must not.* So there is a grounding
scorer that traces figures back to the fact layer, and there is no scorer that
diffs the answer against a reference paragraph.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------


@dataclass
class Check:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        mark = "ok" if self.passed else "FAIL"
        return f"[{mark}] {self.name}{': ' + self.detail if self.detail else ''}"


@dataclass
class ScoreCard:
    case_id: str
    checks: List[Check] = field(default_factory=list)
    latency_ms: float = 0.0
    llm_calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    answered_by: str = ""
    intent: str = ""
    skipped: Optional[str] = None
    error: Optional[str] = None

    @property
    def passed(self) -> bool:
        if self.skipped:
            return True
        if self.error:
            return False
        return all(c.passed for c in self.checks)

    @property
    def failures(self) -> List[Check]:
        return [c for c in self.checks if not c.passed]

    @property
    def zero_token(self) -> bool:
        return self.llm_calls == 0


# ---------------------------------------------------------------------------
# Number extraction
# ---------------------------------------------------------------------------

_NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")

# Below this, a figure in an answer is almost always a count, a rank or a list
# index rather than a claim about the inventory. Grading those produces noise:
# "the top 3 products" is not a hallucination risk, and a scorer that treats it
# as one trains you to ignore the scorer.
_GROUNDING_FLOOR = 100.0


def _numbers_in(text: str) -> List[float]:
    out: List[float] = []
    for raw in _NUMBER.findall(text or ""):
        try:
            out.append(float(raw.replace(",", "")))
        except ValueError:
            continue
    return out


def _round_variants(value: float) -> Set[float]:
    """A figure may be quoted rounded; all of those spellings are grounded."""
    return {
        round(value, 2),
        round(value, 1),
        float(round(value)),
        float(int(value)),
    }


def allowed_numbers(facts: Any, question: str) -> Set[float]:
    """Every figure the fact layer could legitimately produce for this turn.

    Deliberately generous: the scorer is hunting for numbers with no basis in
    the data at all, not for arithmetic that took a different but valid route to
    a total. A false positive here is worse than a missed catch, because it
    makes the suite untrustworthy and people start skipping it.
    """
    allowed: Set[float] = set()

    def add(value: Any) -> None:
        try:
            v = float(value)
        except (TypeError, ValueError):
            return
        allowed.update(_round_variants(v))

    products = list(getattr(facts, "products", []) or [])
    retail_total = 0.0
    cost_total = 0.0
    for p in products:
        qty = getattr(p, "quantity", 0) or 0
        cost = getattr(p, "cost_price", 0.0) or 0.0
        sell = getattr(p, "selling_price", 0.0) or 0.0
        for value in (qty, cost, sell, getattr(p, "min_threshold", 0) or 0):
            add(value)
        add(qty * sell)
        add(qty * cost)
        add(sell - cost)
        retail_total += qty * sell
        cost_total += qty * cost
        # A barcode is a number in the prose and a fact in the catalog.
        try:
            add(str(getattr(p, "barcode", "") or "").strip())
        except Exception:
            pass

    add(retail_total)
    add(cost_total)
    add(retail_total - cost_total)
    add(len(products))

    summary = {}
    try:
        summary = facts.summary() or {}
    except Exception:
        summary = {}
    for value in summary.values():
        if isinstance(value, (int, float)):
            add(value)

    # Numbers the user themselves supplied come back grounded by definition —
    # echoing "add 50 apples" is not an invention.
    for value in _numbers_in(question):
        add(value)

    # Years, so a date stamp is not read as a hallucinated total.
    for year in range(2000, 2101):
        add(year)

    return allowed


# ---------------------------------------------------------------------------
# Scorers
# ---------------------------------------------------------------------------


def _successful_actions(state: Dict[str, Any]) -> List[Dict[str, Any]]:
    out = []
    for action in state.get("executed_actions") or []:
        result = action.get("result") or {}
        if result.get("success"):
            out.append(action)
    return out


def _denied_actions(state: Dict[str, Any]) -> List[Dict[str, Any]]:
    out = []
    for action in state.get("executed_actions") or []:
        result = action.get("result") or {}
        if result.get("error") == "permission_denied":
            out.append(action)
    return out


def score_intent(case, state, facts) -> Optional[Check]:
    want = case.expect.intent
    if not want:
        return None
    got = state.get("intent", "")
    return Check("intent", got == want, f"expected {want}, routed {got or '(none)'}")


def score_response_kind(case, state, facts) -> Optional[Check]:
    want = case.expect.response_kind
    if not want:
        return None
    got = state.get("response_kind", "")
    return Check("response_kind", got == want, f"expected {want}, got {got or '(none)'}")


def score_answered_by(case, state, facts) -> Optional[Check]:
    want = case.expect.answered_by
    if not want:
        return None
    got = state.get("answered_by", "")
    return Check(
        "answered_by",
        got in want,
        f"expected one of {want}, got {got or '(none)'}",
    )


def score_must_contain(case, state, facts) -> Optional[Check]:
    needles = case.expect.must_contain
    if not needles:
        return None
    answer = (state.get("generation") or "").lower()
    missing = [n for n in needles if n.lower() not in answer]
    return Check("must_contain", not missing, f"missing {missing}" if missing else "")


def score_must_not_contain(case, state, facts) -> Optional[Check]:
    needles = case.expect.must_not_contain
    if not needles:
        return None
    answer = (state.get("generation") or "").lower()
    present = [n for n in needles if n.lower() in answer]
    return Check("must_not_contain", not present, f"present {present}" if present else "")


def score_items_are_real_products(case, state, facts) -> Optional[Check]:
    """No row the client renders may point at a product that does not exist.

    This is the exact shape of the invented-product failure: the answer reads
    fine, and one of the cards under it is a placeholder SKU that resolves to
    nothing when tapped.
    """
    if not case.expect.items_are_real_products:
        return None
    items = state.get("items") or []
    if not items:
        return Check("items_are_real_products", True, "no rows returned")

    known_ids = {getattr(p, "id", None) for p in getattr(facts, "products", [])}
    known_barcodes = {
        str(getattr(p, "barcode", "") or "") for p in getattr(facts, "products", [])
    }
    known_ids.discard(None)
    known_barcodes.discard("")

    ghosts = []
    for row in items:
        if not isinstance(row, dict):
            continue
        rid = row.get("id")
        barcode = str(row.get("barcode") or "")
        if rid in known_ids or (barcode and barcode in known_barcodes):
            continue
        ghosts.append(row.get("name") or rid or barcode or "(unnamed row)")

    return Check(
        "items_are_real_products",
        not ghosts,
        f"{len(ghosts)} row(s) not in catalog: {ghosts[:5]}" if ghosts else "",
    )


def score_decoys(case, state, facts) -> Optional[Check]:
    decoys = case.expect.decoy_products
    if not decoys:
        return None
    answer = (state.get("generation") or "").lower()
    found = [d for d in decoys if d.lower() in answer]
    return Check(
        "no_decoy_products",
        not found,
        f"named products that do not exist: {found}" if found else "",
    )


def score_grounded_numbers(case, state, facts) -> Optional[Check]:
    if not case.expect.grounded_numbers:
        return None
    answer = state.get("generation") or ""
    allowed = allowed_numbers(facts, case.question)
    ungrounded = []
    for value in _numbers_in(answer):
        if value < _GROUNDING_FLOOR:
            continue
        if not (_round_variants(value) & allowed):
            ungrounded.append(value)
    return Check(
        "grounded_numbers",
        not ungrounded,
        f"figures with no basis in the data: {ungrounded[:5]}" if ungrounded else "",
    )


def score_writes(case, state, facts) -> Optional[Check]:
    """The tools that were meant to run, ran."""
    wanted = case.expect.writes
    if not wanted:
        return None
    landed = {a.get("tool") for a in _successful_actions(state)}
    # A bulk action reports under "__bulk__" with the real tool inside it.
    for action in _successful_actions(state):
        inner = action.get("inner_tool")
        if inner:
            landed.add(inner)
    missing = [w for w in wanted if w not in landed]
    return Check(
        "writes",
        not missing,
        f"expected {wanted} to succeed; landed {sorted(landed) or 'nothing'}"
        if missing
        else "",
    )


def score_stock_after(case, state, facts) -> Optional[Check]:
    """The catalog holds what it should once the turn is over.

    Read back off the fact layer rather than off the answer, so an agent that
    says it moved 50 units and moved none fails here even when the prose is
    flawless.
    """
    wanted = case.expect.stock_after
    if not wanted:
        return None
    wrong = []
    for barcode, expected in wanted.items():
        product = facts.by_barcode(str(barcode))
        if product is None:
            wrong.append(f"{barcode}: not in catalog")
        elif int(product.quantity) != int(expected):
            wrong.append(f"{barcode}: expected {expected}, holds {product.quantity}")
    return Check("stock_after", not wrong, "; ".join(wrong))


def score_no_writes(case, state, facts) -> Optional[Check]:
    """A question must not move stock.

    Asserted on read-only cases rather than assumed, because the router deciding
    a question is an instruction is a silent, expensive failure: the answer
    still looks right, and the ledger has moved.
    """
    if not case.expect.no_writes:
        return None
    wrote = _successful_actions(state)
    return Check(
        "no_writes",
        not wrote,
        f"executed {[a.get('tool') for a in wrote]}" if wrote else "",
    )


def score_refuses(case, state, facts) -> Optional[Check]:
    if not case.expect.refuses:
        return None
    succeeded = _successful_actions(state)
    denied = _denied_actions(state)
    answer = (state.get("generation") or "").lower()
    said_no = "permission" in answer or "not allowed" in answer or "can't" in answer
    ok = not succeeded and (bool(denied) or said_no)
    if succeeded:
        detail = f"write went through anyway: {[a.get('tool') for a in succeeded]}"
    elif ok:
        detail = ""
    else:
        detail = "nothing was written, but the answer never says the caller lacks permission"
    return Check("refuses", ok, detail)


def score_latency(case, state, facts, latency_ms: float = 0.0) -> Optional[Check]:
    budget = case.expect.max_latency_ms
    if not budget:
        return None
    return Check(
        "latency_budget",
        latency_ms <= budget,
        f"{latency_ms:.0f}ms against a {budget}ms budget",
    )


def score_llm_calls(case, state, facts, llm_calls: int = 0) -> Optional[Check]:
    budget = case.expect.max_llm_calls
    if budget is None:
        return None
    return Check(
        "llm_call_budget",
        llm_calls <= budget,
        f"{llm_calls} call(s) against a budget of {budget}",
    )


# Order matters only for reading the report; every scorer runs.
SCORERS: List[Callable] = [
    score_intent,
    score_response_kind,
    score_answered_by,
    score_must_contain,
    score_must_not_contain,
    score_items_are_real_products,
    score_decoys,
    score_grounded_numbers,
    score_writes,
    score_stock_after,
    score_no_writes,
    score_refuses,
]

BUDGET_SCORERS: List[Callable] = [score_latency, score_llm_calls]
