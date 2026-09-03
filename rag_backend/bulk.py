"""Bulk actions — one instruction, many products.

Every write tool in `nodes.py` targets exactly one product, so a request like
*"add 10 pieces to all low stock items"* had nowhere to land. The resolver was
handed the whole sentence, stripped the command words down to "low", matched
nothing, and the execution agent fell through to `create_product` — which
cheerfully asked for a location and then created a product called *pieces*.
A bulk instruction has to be recognised as a **selector over the catalog**
before anything tries to read it as a single product name.

Three rules hold everything here together:

* A selector is resolved from the live snapshot, never from the model. The set
  of "low stock" products the preview lists is the same set the Reports screen
  shows, because both come from `InventoryFacts`.
* Every affected product is named in the preview before anything is written.
  A bulk write the user cannot see the shape of is a bulk mistake.
* Nothing qualifying is an *answer*, not a failure — "nothing is below its
  threshold" is the correct response to "restock everything low", and it must
  never degrade into asking which product was meant.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

from facts import InventoryFacts, ProductFact

# A chat message is a bad place to authorise a five-hundred-product write. Past
# this the user is asked to narrow the selector instead.
MAX_BULK_TARGETS = 200

# Rows rendered in the confirmation table before it is truncated.
PREVIEW_ROWS = 25


# ---------------------------------------------------------------------------
# Selectors
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Selector:
    key: str
    label: str
    phrases: Tuple[str, ...]
    pick: Callable[[InventoryFacts], List[ProductFact]]
    empty_message: str
    # Phrasings a substring list can't express — "everything that's low".
    patterns: Tuple[str, ...] = ()

    def matches(self, q: str) -> bool:
        if any(phrase in q for phrase in self.phrases):
            return True
        return any(re.search(p, q, re.IGNORECASE) for p in self.patterns)


def _low(facts: InventoryFacts) -> List[ProductFact]:
    """Out of stock first, then low — the same set the Reports screen calls
    "low stock", so the two never disagree."""
    return list(facts.out_of_stock) + list(facts.low_stock)


# Ordered: the first phrase that matches wins, so "out of stock" is tested
# before "low stock" and "dead stock" before the bare word "stock".
SELECTORS: Tuple[Selector, ...] = (
    Selector(
        "out_of_stock",
        "out-of-stock products",
        ("out of stock", "out-of-stock", "outofstock", "zero stock", "no stock left",
         "nil stock", "stocked out", "stockouts", "stock outs"),
        lambda f: list(f.out_of_stock),
        "Nothing is out of stock right now.",
    ),
    Selector(
        "dead_stock",
        "non-moving products",
        ("dead stock", "deadstock", "dead-stock", "not selling", "non moving",
         "non-moving", "slow moving", "slow-moving", "stagnant", "obsolete"),
        lambda f: list(f.dead_stock),
        "Nothing is flagged as non-moving right now.",
    ),
    Selector(
        "overstocked",
        "overstocked products",
        ("overstock", "over stock", "over-stock", "excess stock", "excess inventory",
         "too much stock"),
        lambda f: list(f.overstocked),
        "Nothing is overstocked right now.",
    ),
    Selector(
        "needs_reorder",
        "products below their reorder point",
        ("needs reorder", "need reorder", "needs reordering", "need reordering",
         "below reorder point", "below the reorder point", "due for reorder",
         "reorder list", "reorder point"),
        lambda f: list(f.needs_reorder),
        "Nothing is below its reorder point right now.",
    ),
    Selector(
        "untracked",
        "products with no recorded movement",
        ("untracked", "no movement", "never sold", "no sales recorded",
         "no movement recorded"),
        lambda f: list(f.untracked),
        "Every product has some recorded movement.",
    ),
    Selector(
        "low_stock",
        "low-stock products",
        ("low stock", "low-stock", "lowstock", "running low", "below threshold",
         "below the threshold", "below minimum", "below the minimum",
         "under threshold", "under the threshold", "below min", "low on stock",
         "stock alert", "stock alerts", "needs restock", "need restock",
         "needs restocking", "need restocking", "low items", "low products"),
        _low,
        "Every product is above its safety threshold — nothing is running low.",
        patterns=(
            # "everything that's low", "whatever is low", "the ones running low"
            r"\b(?:everything|anything|whatever|all|any|items?|products?|ones|things)"
            r"(?:\s+\w+){0,3}?\s+(?:is|are|that(?:'s| is| are)?|which (?:is|are))?"
            r"\s*(?:running\s+)?low\b",
            r"\bthat(?:'s| is| are)?\s+(?:running\s+)?low\b",
            # "below its minimum", "under their threshold"
            r"\b(?:below|under|beneath)\s+(?:its|their|the)?\s*"
            r"(?:min(?:imum)?|threshold|safety|reorder point|reorder level)\b",
        ),
    ),
    Selector(
        "all",
        "products in your catalog",
        ("all products", "every product", "all items", "every item", "all skus",
         "every sku", "entire catalog", "whole catalog", "entire inventory",
         "whole inventory", "everything in stock", "all my stock",
         "all my products", "all the products", "all the items"),
        lambda f: list(f.products),
        "Your catalog is empty.",
    ),
)

_SELECTOR_BY_KEY = {s.key: s for s in SELECTORS}

# "all", "every", "each"… on its own is not a selector, but paired with one it
# is what separates "restock all low stock items" from a product literally
# named "All Purpose Flour".
_SCOPE_RE = re.compile(
    r"\b(all|every|each|everything|any|entire|whole|bulk|both|multiple)\b", re.IGNORECASE
)

# "top 5 low stock items" caps the selection; the 5 is not a quantity.
_LIMIT_RE = re.compile(r"\b(?:top|first|bottom|last)\s+(\d{1,3})\b", re.IGNORECASE)


def _category_names(facts: InventoryFacts) -> List[str]:
    """Every category the company actually uses.

    The configured list and the values on products can differ — a workspace
    that never filled in its category collection still files products under
    names the user recognises, and those are what they type.
    """
    seen: Dict[str, str] = {}
    for cat in facts.categories or []:
        name = str(cat.get("name", "")).strip()
        if name:
            seen.setdefault(name.lower(), name)
    for p in facts.products:
        name = (p.category or "").strip()
        if name:
            seen.setdefault(name.lower(), name)
    # Longest first: "Dairy Chilled" must win over "Dairy".
    return sorted(seen.values(), key=len, reverse=True)


def _category_selector(question: str, facts: InventoryFacts) -> Optional[Selector]:
    """A selector over one of the company's own categories."""
    q = question.lower()
    for name in _category_names(facts):
        if len(name) < 3:
            continue
        if re.search(rf"\b{re.escape(name.lower())}\b", q):
            cat_name = name
            return Selector(
                f"category:{cat_name}",
                f"products in **{cat_name}**",
                (),
                lambda f, n=cat_name: [
                    p for p in f.products if (p.category or "").lower() == n.lower()
                ],
                f"No products are in the **{cat_name}** category.",
            )
    return None


def _location_selector(question: str, facts: InventoryFacts) -> Optional[Selector]:
    """A selector over one of the company's own locations."""
    q = question.lower()
    for loc in facts.known_locations or []:
        name = str(loc).strip()
        if len(name) < 3:
            continue
        if re.search(rf"\b{re.escape(name.lower())}\b", q):
            return Selector(
                f"location:{name}",
                f"products at **{name}**",
                (),
                lambda f, n=name: [
                    p for p in f.products if n in (p.location_quantities or {})
                    or (p.location or "").lower() == n.lower()
                ],
                f"No products are held at **{name}**.",
            )
    return None


def find_selector(question: str, facts: InventoryFacts) -> Optional[Selector]:
    """The catalog subset a question is about, or None when it names none."""
    q = " ".join((question or "").lower().split())
    if not q:
        return None

    # A category or location only counts as a selector when the sentence is
    # plainly talking about a group — otherwise "add 10 Dairy Milk" would be
    # read as "every product in Dairy".
    narrow = (
        _category_selector(q, facts) or _location_selector(q, facts)
        if _SCOPE_RE.search(q)
        else None
    )

    for selector in SELECTORS:
        if not selector.matches(q):
            continue
        if narrow is None:
            return selector
        if selector.key == "all":
            # "every product in Dairy" is the category, not the catalog.
            return narrow
        return _intersect(selector, narrow)

    return narrow


def _both(left: List[ProductFact], right: List[ProductFact]) -> List[ProductFact]:
    """Products in both lists, in the left list's order. ProductFact is a
    dataclass with dict fields, so it is unhashable — ids do the work."""
    ids = {p.id for p in right}
    return [p for p in left if p.id in ids]


def _intersect(base: Selector, narrow: Selector) -> Selector:
    """"Low stock in Dairy" is both conditions, not whichever matched first."""
    return Selector(
        f"{base.key}+{narrow.key}",
        f"{base.label} in {narrow.label.replace('products in ', '').replace('products at ', '')}",
        (),
        lambda f: _both(base.pick(f), narrow.pick(f)),
        f"{base.empty_message.rstrip('.')} in that group.",
    )


def selector_for_key(key: str, facts: InventoryFacts) -> Optional[Selector]:
    """Resolve the selector key a tool call passed, including `category:X`."""
    key = (key or "").strip()
    if key in _SELECTOR_BY_KEY:
        return _SELECTOR_BY_KEY[key]
    if key.startswith("category:"):
        return _category_selector(key.split(":", 1)[1], facts)
    if key.startswith("location:"):
        return _location_selector(key.split(":", 1)[1], facts)
    return None


# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

_ADD_WORDS = ("add", "increase", "restock", "top up", "topup", "received", "receive",
              "plus", "put", "stock in", "stock-in", "replenish", "refill",
              "bump", "boost", "raise stock", "bring in")
# "Restock everything low" needs no number: the target is each product's own
# threshold. "Add to everything low" does — there is nothing to infer from.
_TOPUP_WORDS = ("restock", "replenish", "refill", "top up", "topup", "bring back")
_DEDUCT_WORDS = ("deduct", "remove", "reduce", "subtract", "minus", "sold", "damaged",
                 "write off", "write-off", "decrease", "stock out", "stock-out")
_ORDER_WORDS = ("purchase order", "create po", "raise a po", "raise po", "reorder",
                "re-order", "order", "buy", "procure")
_THRESHOLD_WORDS = ("threshold", "min level", "minimum level", "reorder point",
                    "safety level", "minimum", "min stock", "alert level")
_AUDIT_WORDS = ("set stock to", "set the stock to", "counted", "physical count",
                "audit to")

# "bring everything up to its minimum" — the quantity differs per product and
# only the snapshot knows it. This is the reading that makes "restock all low
# stock items" useful rather than uniform-and-wrong.
_TO_MIN_RE = re.compile(
    r"\b(?:up |back )?to (?:its |their |the )?(?:min(?:imum)?|threshold|reorder point|safety)"
    r"|\bback to (?:min(?:imum)?|threshold|healthy|safe)"
    r"|\b(?:fill|bring|top) (?:them |it |everything )?(?:up|back)\b",
    re.IGNORECASE,
)

# "order what's needed" — per-product suggested quantity from the fact layer.
_SUGGESTED_RE = re.compile(
    r"\b(?:what(?:'s| is)? needed|as needed|suggested|recommended|the right amount"
    r"|enough|whatever (?:they|it) need)\b",
    re.IGNORECASE,
)


def _any(text: str, words: Tuple[str, ...]) -> bool:
    return any(w in text for w in words)


# A bulk *write* has to be told apart from a bulk *question*. "Give me the
# reorder list" names the same set of products as "order what every low stock
# item needs" and means something entirely different; answering the first with
# a confirmation card would be worse than useless.
_QUESTION_LEAD_RE = re.compile(
    r"^(what|which|who|when|why|how|where|show|list|give|tell|display|find|see"
    r"|is|are|do|does|did|can|could|should|would|will|any)\b",
    re.IGNORECASE,
)
_LIST_REQUEST_RE = re.compile(
    r"\b(list|report|table|summary|overview|breakdown|which ones|show me|status)\b",
    re.IGNORECASE,
)

_OPERATION_WORDS = _ADD_WORDS + _DEDUCT_WORDS + _ORDER_WORDS + _AUDIT_WORDS + (
    "set", "threshold", "audit",
)


def _reads_as_write(q: str, qty: Optional[int]) -> bool:
    """Is this an instruction, or a question about the same products?"""
    if _LIST_REQUEST_RE.search(q):
        return False
    if _QUESTION_LEAD_RE.match(q):
        # "Can you add 10 units to every low stock item" is still an
        # instruction — but only when the scope, the verb and the number are
        # all there, leaving nothing to interpret.
        return bool(qty is not None and _SCOPE_RE.search(q) and _any(q, _ADD_WORDS + _DEDUCT_WORDS))
    return True


def is_bulk_write(question: str) -> bool:
    """Facts-free check for the router: does this instruct a change to a group?

    Deliberately conservative. A miss costs a model call, which can still reach
    the same place through the `bulk_action` tool; a false positive would turn
    a question into a confirmation card.
    """
    q = " ".join((question or "").lower().split())
    if not q:
        return False
    if not any(phrase in q for phrase in
               (p for selector in SELECTORS for p in selector.phrases)):
        return False
    if not _any(q, _OPERATION_WORDS) and not _TO_MIN_RE.search(q):
        return False
    return _reads_as_write(q, _quantity(q))


def _quantity(question: str) -> Optional[int]:
    """The quantity in a bulk instruction, ignoring a `top N` cap."""
    cleaned = _LIMIT_RE.sub(" ", question or "")
    # A percentage is not a unit count; refuse rather than mistake 20% for 20.
    if re.search(r"\d\s*%", cleaned):
        return None
    match = re.search(r"\b(\d{1,6})\b", cleaned)
    return int(match.group(1)) if match else None


def _limit(question: str) -> Optional[int]:
    match = _LIMIT_RE.search(question or "")
    return int(match.group(1)) if match else None


@dataclass
class BulkPlan:
    """A resolved multi-product instruction, ready to preview."""

    tool: str                       # the per-product write tool
    selector_key: str
    selector_label: str
    targets: List[ProductFact]
    args: Dict[str, Any] = field(default_factory=dict)
    # Set when the quantity is computed per product rather than shared.
    mode: str = "fixed"             # fixed | to_min | suggested
    truncated_from: int = 0

    @property
    def count(self) -> int:
        return len(self.targets)

    def qty_for(self, product: ProductFact) -> int:
        """Units this product moves by, under this plan."""
        if self.mode == "to_min":
            return max(0, product.min_threshold - product.quantity)
        if self.mode == "suggested":
            return int(product.suggested_reorder_qty or 0) or max(
                0, product.min_threshold - product.quantity
            )
        if self.tool == "update_stock":
            return int(self.args.get("qty_change", 0))
        if self.tool == "create_purchase_order":
            return int(self.args.get("reorder_qty", 0))
        return 0

    def to_action(self) -> Dict[str, Any]:
        """The shape stored as a pending action and echoed to the client."""
        return {
            "tool": "__bulk__",
            "inner_tool": self.tool,
            "selector": self.selector_key,
            "selector_label": self.selector_label,
            "mode": self.mode,
            "args": dict(self.args),
            "count": self.count,
            "product_name": f"{self.count} {self.selector_label}",
            "barcode": "",
            "product_id": "",
            "targets": [
                {
                    "id": p.id,
                    "barcode": p.barcode,
                    "name": p.name,
                    "stock": p.quantity,
                    "threshold": p.min_threshold,
                    "change": self.qty_for(p),
                }
                for p in self.targets
            ],
        }


def parse(question: str, facts: InventoryFacts) -> Optional[BulkPlan]:
    """Read a bulk instruction, or return None so single-product handling runs.

    Returns a plan even when the selector matches nothing — the caller needs to
    say *"nothing is low"* rather than fall through to product creation.
    """
    q = " ".join((question or "").lower().split())
    if not q:
        return None

    selector = find_selector(q, facts)
    if selector is None:
        return None

    qty = _quantity(q)
    if not _reads_as_write(q, qty):
        return None

    to_min = bool(_TO_MIN_RE.search(q))
    suggested = bool(_SUGGESTED_RE.search(q))

    tool: Optional[str] = None
    args: Dict[str, Any] = {}
    mode = "fixed"

    if _any(q, _THRESHOLD_WORDS) and re.search(r"\b(set|change|update|make|raise|lower)\b", q):
        if qty is None:
            return None
        tool = "set_reorder_threshold"
        args = {"new_threshold": qty}
    elif _any(q, _AUDIT_WORDS):
        if qty is None:
            return None
        tool = "audit_inventory"
        args = {"actual_stock": qty, "notes": "Bulk audit via Ask AI"}
    elif _any(q, _ORDER_WORDS) and not _any(q, _ADD_WORDS[:1]):
        tool = "create_purchase_order"
        if qty is not None and not suggested:
            args = {"reorder_qty": qty, "supplier_name": ""}
        else:
            mode = "suggested"
            args = {"supplier_name": ""}
    elif _any(q, _DEDUCT_WORDS):
        if qty is None:
            return None
        tool = "update_stock"
        args = {"qty_change": -qty, "reason": "Bulk adjustment via Ask AI"}
    elif _any(q, _ADD_WORDS):
        tool = "update_stock"
        if to_min or (qty is None and (suggested or _any(q, _TOPUP_WORDS))):
            mode = "to_min"
            args = {"reason": "Bulk top-up to threshold via Ask AI"}
        elif qty is None:
            return None
        else:
            args = {"qty_change": qty, "reason": "Bulk adjustment via Ask AI"}
    else:
        # A selector with no operation is a question ("what is low?"), not a
        # write. Analytics already answers those well.
        return None

    return build(tool, selector, facts, args, mode, limit=_limit(q))


def build(
    tool: str,
    selector: Selector,
    facts: InventoryFacts,
    args: Dict[str, Any],
    mode: str = "fixed",
    limit: Optional[int] = None,
) -> BulkPlan:
    """Resolve a selector to live products and cap the blast radius."""
    targets = selector.pick(facts)

    if tool == "update_stock" and mode in ("to_min", "suggested"):
        # Products already at or above their threshold move by zero; listing
        # them in the preview would overstate what the change does.
        targets = [p for p in targets if p.min_threshold > p.quantity]
    if tool == "create_purchase_order" and mode == "suggested":
        targets = [
            p for p in targets
            if (p.suggested_reorder_qty or 0) > 0 or p.min_threshold > p.quantity
        ]

    truncated_from = 0
    if limit and limit > 0:
        targets = targets[:limit]
    elif len(targets) > MAX_BULK_TARGETS:
        truncated_from = len(targets)
        targets = targets[:MAX_BULK_TARGETS]

    return BulkPlan(
        tool=tool,
        selector_key=selector.key,
        selector_label=selector.label,
        targets=targets,
        args=args,
        mode=mode,
        truncated_from=truncated_from,
    )


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

_VERB = {
    "update_stock": "Stock change",
    "create_purchase_order": "Purchase order",
    "set_reorder_threshold": "Reorder threshold",
    "audit_inventory": "Stock count",
}


def empty_message(plan: BulkPlan, facts: InventoryFacts) -> str:
    """What to say when the selector is valid but matches nothing."""
    selector = selector_for_key(plan.selector_key, facts)
    base = selector.empty_message if selector else "Nothing matched that."
    if plan.mode in ("to_min", "suggested"):
        return f"{base} Nothing needs topping up, so I've made no changes."
    return f"{base} I've made no changes."


def preview(plan: BulkPlan, facts: InventoryFacts) -> str:
    """The confirmation card body: every product this touches, and by how much."""
    rows: List[str] = []
    total_units = 0
    total_cost = 0.0

    for p in plan.targets[:PREVIEW_ROWS]:
        change = plan.qty_for(p)
        if plan.tool == "update_stock":
            # A deduction bigger than the free stock is refused by the write,
            # not clamped — so the row must not promise a projected zero.
            blocked = change < 0 and p.available_qty < abs(change)
            after = (
                f"_can't — {p.available_qty} free_"
                if blocked
                else f"**{p.quantity + change}**"
            )
            rows.append(
                f"| **{p.name}** | `{p.barcode}` | {p.quantity} | **{change:+d}** | "
                f"{after} |"
            )
        elif plan.tool == "create_purchase_order":
            rows.append(
                f"| **{p.name}** | `{p.barcode}` | {p.quantity} | **{change}** | "
                f"{change * p.cost_price:,.2f} |"
            )
        elif plan.tool == "set_reorder_threshold":
            rows.append(
                f"| **{p.name}** | `{p.barcode}` | {p.quantity} | {p.min_threshold} | "
                f"**{plan.args.get('new_threshold', 0)}** |"
            )
        else:  # audit_inventory
            counted = int(plan.args.get("actual_stock", 0))
            rows.append(
                f"| **{p.name}** | `{p.barcode}` | {p.quantity} | **{counted}** | "
                f"**{counted - p.quantity:+d}** |"
            )

    for p in plan.targets:
        change = plan.qty_for(p)
        if plan.tool == "update_stock" and change < 0 and p.available_qty < abs(change):
            continue  # this one will be refused; it is not part of the total
        total_units += abs(change)
        total_cost += change * p.cost_price

    headers = {
        "update_stock": ["Product", "Barcode", "Now", "Change", "After"],
        "create_purchase_order": ["Product", "Barcode", "Stock", "Order", "Cost"],
        "set_reorder_threshold": ["Product", "Barcode", "Stock", "Old min", "New min"],
        "audit_inventory": ["Product", "Barcode", "System", "Counted", "Diff"],
    }[plan.tool]

    table = "\n".join(
        ["| " + " | ".join(headers) + " |",
         "| " + " | ".join([":---"] * len(headers)) + " |"]
        + rows
    )

    hidden = len(plan.targets) - len(rows)
    more = f"\n\n_{hidden} more not shown — all {plan.count} are included._" if hidden > 0 else ""

    if plan.mode == "to_min":
        headline = (
            f"Top **{plan.count} {plan.selector_label}** back up to their own "
            f"thresholds — **{total_units} units** in total."
        )
    elif plan.mode == "suggested":
        headline = (
            f"Draft purchase orders for **{plan.count} {plan.selector_label}** at the "
            f"quantity each one needs — **{total_units} units**, "
            f"**{total_cost:,.2f}** at cost."
        )
    elif plan.tool == "update_stock":
        delta = int(plan.args.get("qty_change", 0))
        headline = (
            f"{'Add' if delta > 0 else 'Deduct'} **{abs(delta)} units** "
            f"{'to' if delta > 0 else 'from'} **each** of **{plan.count} "
            f"{plan.selector_label}** — **{total_units} units** in total."
        )
    elif plan.tool == "create_purchase_order":
        headline = (
            f"Draft **{plan.count}** purchase orders of "
            f"**{plan.args.get('reorder_qty', 0)} units** each — "
            f"**{total_cost:,.2f}** at cost."
        )
    elif plan.tool == "set_reorder_threshold":
        headline = (
            f"Set the reorder threshold to **{plan.args.get('new_threshold', 0)}** on "
            f"**{plan.count} {plan.selector_label}**."
        )
    else:
        headline = (
            f"Record a counted stock of **{plan.args.get('actual_stock', 0)}** on "
            f"**{plan.count} {plan.selector_label}**."
        )

    warning = ""
    if plan.truncated_from:
        warning = (
            f"\n\n> **{plan.truncated_from} products matched.** I've capped this at "
            f"{MAX_BULK_TARGETS}. Narrow it down — by category or location — to "
            f"cover the rest."
        )
    if plan.tool == "update_stock" and int(plan.args.get("qty_change", 0)) < 0:
        short = [p.name for p in plan.targets if p.available_qty < abs(plan.qty_for(p))]
        if short:
            warning += (
                f"\n\n> **{len(short)} product(s) don't have that much unreserved "
                f"stock** — {', '.join(short[:3])}"
                + ("…" if len(short) > 3 else "")
                + ". A stock change is refused rather than clamped, so those "
                "will be reported as failed and left untouched; the rest still "
                "go through."
            )

    return (
        f"### Confirm bulk change\n\n{headline}\n\n"
        + table
        + more
        + warning
        + "\n\nReply **Confirm** to apply to all of them, or **Cancel** to discard."
    )


# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

def execute(
    action: Dict[str, Any],
    facts: InventoryFacts,
    company_id: str,
    apply_one: Callable[[str, ProductFact, Dict[str, Any]], Dict[str, Any]],
) -> Tuple[str, Dict[str, Any]]:
    """Apply a confirmed bulk action product by product.

    `apply_one` performs a single write so this module stays free of Firestore.
    Failures are reported per product rather than aborting the batch: a supplier
    missing on one item is no reason to leave the other forty unchanged.
    """
    inner = action.get("inner_tool", "update_stock")
    args = dict(action.get("args") or {})
    mode = action.get("mode", "fixed")
    targets = action.get("targets") or []

    applied: List[Dict[str, Any]] = []
    failed: List[Dict[str, Any]] = []
    skipped: List[str] = []

    for row in targets:
        product = facts.lookup(row.get("barcode", "")) or facts.by_id(row.get("id", ""))
        if product is None:
            failed.append({"name": row.get("name", "?"), "error": "no longer in catalog"})
            continue

        # Recompute against fresh facts: a plan previewed a minute ago must not
        # write a stale delta if the stock moved in the meantime.
        call_args = dict(args)
        if inner == "update_stock":
            qty = (
                max(0, product.min_threshold - product.quantity)
                if mode == "to_min"
                else int(args.get("qty_change", 0))
            )
            if qty == 0:
                skipped.append(product.name)
                continue
            call_args["qty_change"] = qty
        elif inner == "create_purchase_order":
            qty = (
                int(product.suggested_reorder_qty or 0)
                or max(0, product.min_threshold - product.quantity)
                if mode == "suggested"
                else int(args.get("reorder_qty", 0))
            )
            if qty <= 0:
                skipped.append(product.name)
                continue
            call_args["reorder_qty"] = qty

        result = apply_one(inner, product, call_args)
        if result.get("success"):
            applied.append({"name": product.name, "result": result})
        else:
            failed.append(
                {"name": product.name, "error": result.get("error", "unknown error")}
            )

    message = _report(inner, mode, applied, failed, skipped)
    record = {
        "tool": "bulk_" + inner,
        "result": {
            "success": bool(applied),
            "applied": len(applied),
            "failed": len(failed),
            "skipped": len(skipped),
            "selector": action.get("selector", ""),
            "products": [a["name"] for a in applied],
            "errors": failed,
        },
    }
    return message, record


def _report(
    inner: str,
    mode: str,
    applied: List[Dict[str, Any]],
    failed: List[Dict[str, Any]],
    skipped: List[str],
) -> str:
    if not applied and not failed:
        return "Nothing needed changing — no products were affected."

    verb = {
        "update_stock": "Updated stock on",
        "create_purchase_order": "Drafted purchase orders for",
        "set_reorder_threshold": "Changed the reorder threshold on",
        "audit_inventory": "Recorded a stock count on",
    }.get(inner, "Updated")

    lines: List[str] = []
    if applied:
        lines.append(f"Done. {verb} **{len(applied)} products**.")
        rows = []
        for entry in applied[:PREVIEW_ROWS]:
            result = entry["result"]
            if inner == "update_stock":
                rows.append(
                    f"| **{entry['name']}** | {result.get('old_stock', '?')} → "
                    f"**{result.get('new_stock', '?')}** |"
                )
            elif inner == "create_purchase_order":
                rows.append(
                    f"| **{entry['name']}** | {result.get('reorder_qty', 0)} units "
                    f"· {result.get('po_id', '')} |"
                )
            elif inner == "set_reorder_threshold":
                rows.append(
                    f"| **{entry['name']}** | {result.get('old_threshold', '?')} → "
                    f"**{result.get('new_threshold', '?')}** |"
                )
            else:
                rows.append(
                    f"| **{entry['name']}** | set to "
                    f"**{result.get('actual_stock', '?')}** |"
                )
        header = {
            "update_stock": "Stock",
            "create_purchase_order": "Ordered",
            "set_reorder_threshold": "Threshold",
        }.get(inner, "Result")
        lines.append(
            "\n".join([f"| Product | {header} |", "| :--- | :--- |"] + rows)
        )
        if len(applied) > PREVIEW_ROWS:
            lines.append(f"_…and {len(applied) - PREVIEW_ROWS} more._")

    if skipped:
        shown = ", ".join(skipped[:5]) + ("…" if len(skipped) > 5 else "")
        lines.append(
            f"> Skipped **{len(skipped)}** already at or above target: {shown}"
        )

    if failed:
        rows = [f"| **{f['name']}** | {f['error']} |" for f in failed[:10]]
        lines.append(
            f"> **{len(failed)} failed** and were left unchanged:\n\n"
            + "\n".join(["| Product | Why |", "| :--- | :--- |"] + rows)
        )

    return "\n\n".join(lines)
