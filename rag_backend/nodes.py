"""
Agent nodes.

The rewrite fixes the structural problems that made the assistant unreliable:

* `retrieve_node` used to branch on an intent literal (`"ACTION"`) the router
  never emitted, so the execution agent fell through to the knowledge branch and
  received a one-line summary. It had to *guess* barcodes. That is fixed — it
  now gets resolved product facts for exactly the SKUs the question is about.
* The analytics node built a full-catalog context block and then never read it.
  It now consumes the fact layer directly.
* Tool results were `str(dict)` — the model was reading Python repr. They are
  compact JSON now.
* Mutations preview first and execute from server-side structured state, instead
  of regex-scraping a previously rendered markdown table.
"""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any, Dict, List, Optional, Tuple

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage
from pydantic import BaseModel, Field

import bulk
import deterministic
import llm as llm_factory
import verify
import writes
from facts import InventoryFacts, ProductFact, fact_store
from guardrails import InventoryGuardrails
from pending import is_cancellation, is_confirmation, pending_actions
from resolver import ProductResolver
from state import GraphState

MAX_HISTORY_TURNS = 6
MAX_HISTORY_CHARS = 600
MAX_TOOL_ITERATIONS = 4
MAX_CONTEXT_PRODUCTS = 12


# ---------------------------------------------------------------------------
# Tool schemas
# ---------------------------------------------------------------------------

class search_products(BaseModel):
    """Find products by name, partial name, or barcode. Use this before any action
    when you are not certain which product the user means."""

    query: str = Field(description="Product name, partial name, or barcode.")
    limit: int = Field(default=5, description="Maximum matches to return.")


class get_product(BaseModel):
    """Get full live detail for one product: stock, availability, burn rate,
    days of cover, reorder point, price."""

    product: str = Field(description="Exact product name or barcode.")


class list_products(BaseModel):
    """List products in a named category of interest."""

    filter: str = Field(
        description=(
            "One of: low_stock, out_of_stock, dead_stock, untracked, "
            "needs_reorder, overstocked, top_sellers, all"
        )
    )
    limit: int = Field(default=15, description="Maximum rows to return.")


class inventory_summary(BaseModel):
    """Aggregate counts and valuation across the whole catalog."""


class simulate_financial_impact(BaseModel):
    """Model the cash and margin effect of buying or selling a quantity."""

    product: str = Field(description="Exact product name or barcode.")
    action_type: str = Field(description="One of: reorder, sell, clearance.")
    qty: int = Field(description="Number of units involved.")


class update_stock(BaseModel):
    """Change an existing product's stock level. Positive adds, negative deducts."""

    product: str = Field(description="Exact product name or barcode.")
    qty_change: int = Field(description="Units to add (positive) or deduct (negative).")
    reason: str = Field(default="AI adjustment", description="Why the stock changed.")
    location: str = Field(
        default="",
        description="Which location the stock moves at. Required when the product holds stock in more than one.",
    )


class create_purchase_order(BaseModel):
    """Draft a purchase order to a supplier."""

    product: str = Field(description="Exact product name or barcode.")
    reorder_qty: int = Field(description="Units to order.")
    supplier_name: str = Field(default="", description="Supplier, if specified.")


class transfer_stock(BaseModel):
    """Move stock between two locations."""

    product: str = Field(description="Exact product name or barcode.")
    from_location: str = Field(description="Source location.")
    to_location: str = Field(description="Destination location.")
    qty: int = Field(description="Units to move.")


class audit_inventory(BaseModel):
    """Set stock to a physically counted quantity."""

    product: str = Field(description="Exact product name or barcode.")
    actual_stock: int = Field(description="Counted quantity.")
    notes: str = Field(default="Physical audit", description="Audit notes.")


class create_product(BaseModel):
    """Add a brand new product to the catalog.

    Only call this when the product genuinely does not exist yet — search first.
    Leave a field out rather than guessing it: a wrong price or shelf looks
    authoritative and quietly corrupts stock valuation and reporting.
    """

    name: str = Field(description="Full product name, as it should appear in the catalog.")
    quantity: int = Field(description="Opening stock quantity.")
    location: str = Field(default="", description="Where the stock sits. Must be one of the company's locations.")
    barcode: str = Field(default="", description="Barcode, if the user gave one.")
    category_name: str = Field(default="", description="Category name. Must be one the company already uses.")
    cost_price: float = Field(default=0.0, description="Purchase cost per unit.")
    selling_price: float = Field(default=0.0, description="Sale price per unit.")
    low_stock_threshold: int = Field(default=10, description="Reorder alert level.")
    unit: str = Field(default="pcs", description="Unit of measure, e.g. pcs, box, Tube.")
    brand: str = Field(default="", description="Manufacturer or brand.")
    size: str = Field(default="", description="Pack size, e.g. 30gm, Pack of 5.")
    vendor_name: str = Field(default="", description="Supplier, if given.")


class set_reorder_threshold(BaseModel):
    """Change a product's low-stock safety threshold."""

    product: str = Field(description="Exact product name or barcode.")
    new_threshold: int = Field(description="New minimum threshold.")


class bulk_action(BaseModel):
    """Apply one change to EVERY product in a named group.

    Use this — never the single-product tools, and never create_product — when
    the request is about a *set* of products rather than one: "all low stock
    items", "everything out of stock", "every product in Dairy". The group is
    resolved from live data, and the user confirms the full list before
    anything is written.
    """

    operation: str = Field(
        description=(
            "add_stock (add `qty` to each), deduct_stock (remove `qty` from each), "
            "top_up_to_min (raise each to its own threshold), "
            "create_purchase_order (draft a PO per product), "
            "set_threshold (set each product's reorder threshold to `qty`), "
            "audit (record a counted stock of `qty` on each)."
        )
    )
    selector: str = Field(
        description=(
            "Which products: low_stock, out_of_stock, needs_reorder, dead_stock, "
            "overstocked, untracked, all, category:<name>, or location:<name>. "
            "Use a category or location name the company actually has."
        )
    )
    qty: int = Field(
        default=0,
        description=(
            "Units per product. Leave 0 for top_up_to_min, and for "
            "create_purchase_order when each product should be ordered at its "
            "own suggested quantity."
        ),
    )


READ_TOOLS = [
    search_products,
    get_product,
    list_products,
    inventory_summary,
    simulate_financial_impact,
]
WRITE_TOOLS = [
    create_product,
    update_stock,
    create_purchase_order,
    transfer_stock,
    audit_inventory,
    set_reorder_threshold,
    bulk_action,
]
EXECUTION_TOOLS = READ_TOOLS + WRITE_TOOLS
ANALYTICS_TOOLS = READ_TOOLS

WRITE_TOOL_NAMES = {t.__name__ for t in WRITE_TOOLS}

# The `AppPermissions` key each write tool corresponds to, using the same
# strings the Flutter client uses. Everything here writes through the Firebase
# Admin SDK, which bypasses firestore.rules entirely — so without this map a
# viewer who is denied `canStockIn` in the app could simply ask the assistant to
# add stock instead, and it would succeed.
WRITE_TOOL_PERMISSIONS = {
    "create_product": "canAddProducts",
    "update_stock": "canAdjustStock",
    "create_purchase_order": "canCreatePurchaseOrders",
    "transfer_stock": "canTransfer",
    "audit_inventory": "canAdjustStock",
    "set_reorder_threshold": "canEditProducts",
}

# What each bulk operation maps to, so one grant check covers both routes: a
# bulk stock change is still a stock change, and must not become a way around
# `canAdjustStock`.
BULK_OPERATIONS = {
    "add_stock": ("update_stock", "fixed"),
    "deduct_stock": ("update_stock", "fixed"),
    "top_up_to_min": ("update_stock", "to_min"),
    "restock_to_min": ("update_stock", "to_min"),
    "create_purchase_order": ("create_purchase_order", "suggested"),
    "purchase_order": ("create_purchase_order", "suggested"),
    "reorder": ("create_purchase_order", "suggested"),
    "set_threshold": ("set_reorder_threshold", "fixed"),
    "audit": ("audit_inventory", "fixed"),
}


def permission_for_tool(tool: str) -> str:
    """The permission [tool] needs, or '' when it only reads."""
    return WRITE_TOOL_PERMISSIONS.get(tool, "")


def may_run_tool(tool: str, permissions) -> bool:
    """Whether a caller holding [permissions] may run [tool].

    [permissions] is the set of granted keys, or None when the caller's grants
    could not be established — in which case reads are still fine but writes are
    refused, so a Firestore hiccup denies rather than allows.
    """
    needed = permission_for_tool(tool)
    if not needed:
        return True
    if permissions is None:
        return False
    return "*" in permissions or needed in permissions


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TABLE_LINE = re.compile(r"^\s*\|.*\|\s*$", re.MULTILINE)
_TAGGED_BLOCK = re.compile(r"\[(?:STATS|ACTION|PENDING):.*?\]", re.DOTALL)


def sanitize_history(history: Optional[List[Dict[str, str]]]) -> List[Any]:
    """Trim history to what actually helps the model.

    A single rendered audit table is ~800 tokens; ten turns of them crowd out the
    live data. Tables are stripped (their content is regenerated from facts
    anyway) and the transcript is capped.
    """
    if not history:
        return []
    messages: List[Any] = []
    for msg in history[-(MAX_HISTORY_TURNS * 2):]:
        role = (msg.get("role") or "").lower()
        content = msg.get("content") or ""
        content = _TAGGED_BLOCK.sub("", content)
        content = _TABLE_LINE.sub("", content)
        content = re.sub(r"\n{3,}", "\n\n", content).strip()
        if not content:
            continue
        if len(content) > MAX_HISTORY_CHARS:
            content = content[:MAX_HISTORY_CHARS].rstrip() + "..."
        if role == "user":
            messages.append(HumanMessage(content=content))
        elif role in ("assistant", "model", "ai"):
            messages.append(AIMessage(content=content))
    return messages[-(MAX_HISTORY_TURNS * 2):]


def business_context(business_type: str) -> str:
    return {
        "retail_store": "a retail store owner managing shelf stock and restocking",
        "restaurant": "a restaurant manager tracking ingredients, supplies and vendor orders",
        "clinic": "a clinic administrator managing medical consumables and equipment",
        "warehouse": "a warehouse manager handling bulk storage, zone transfers and dispatch",
        "manufacturer": "a production supervisor tracking raw materials and finished goods",
        "pharmacy": "a pharmacy owner managing medication stock, expiry and reorders",
        "ecommerce": "an e-commerce seller managing SKU stock and fulfilment levels",
    }.get(business_type, "a retail store owner managing shelf stock and restocking")


def _json(value: Any) -> str:
    try:
        return json.dumps(value, default=str, separators=(",", ":"))
    except Exception:
        return json.dumps({"error": "unserialisable result"})


async def stream_message(client: Any, messages: List[Any], tier: str) -> Any:
    """Invoke the model in streaming mode and accumulate the chunks.

    Streaming is what makes time-to-first-token ~300ms instead of the full
    generation time. Accumulating the chunks rather than using `ainvoke` means
    we still get a complete message with parsed `tool_calls` at the end, so the
    agent loop works unchanged.
    """
    merged = None
    try:
        async for chunk in client.astream(messages):
            merged = chunk if merged is None else merged + chunk
    except Exception:
        if merged is None:
            raise
    if merged is None:
        merged = await client.ainvoke(messages)
    llm_factory.usage.record(tier, merged)
    return merged


def _resolver(facts: InventoryFacts) -> ProductResolver:
    cached = getattr(facts, "_resolver", None)
    if cached is None:
        cached = ProductResolver(facts.products)
        try:
            object.__setattr__(facts, "_resolver", cached)
        except Exception:
            pass
    return cached


# ---------------------------------------------------------------------------
# Read-only tool execution
# ---------------------------------------------------------------------------

_FILTERS = {
    "low_stock": lambda f: f.low_stock,
    "out_of_stock": lambda f: f.out_of_stock,
    "dead_stock": lambda f: f.dead_stock,
    "no_history": lambda f: f.untracked,
    "untracked": lambda f: f.untracked,
    "needs_reorder": lambda f: f.needs_reorder,
    "overstocked": lambda f: f.overstocked,
    "at_risk": lambda f: f.at_risk,
    "all": lambda f: f.products,
}


def run_read_tool(name: str, args: Dict[str, Any], facts: InventoryFacts) -> Dict[str, Any]:
    resolver = _resolver(facts)

    if name == "search_products":
        limit = max(1, min(int(args.get("limit", 5) or 5), 10))
        res = resolver.resolve(str(args.get("query", "")), limit=limit)
        return {
            "status": res.status,
            "matches": [
                {**c.product.brief(), "confidence": round(c.score, 2)}
                for c in res.candidates[:limit]
            ],
        }

    if name == "get_product":
        res = resolver.resolve(str(args.get("product", "")))
        if res.status == "resolved":
            return {"status": "ok", "product": res.product.to_dict()}
        if res.status == "ambiguous":
            return {"status": "ambiguous", "candidates": res.options()}
        return {"status": "not_found", "query": args.get("product", "")}

    if name == "list_products":
        key = str(args.get("filter", "all")).lower().strip()
        limit = max(1, min(int(args.get("limit", 15) or 15), 30))
        if key == "top_sellers":
            items = sorted(
                (p for p in facts.products if p.units_out_window > 0),
                key=lambda p: -p.units_out_window,
            )
        else:
            items = _FILTERS.get(key, _FILTERS["all"])(facts)
        return {
            "filter": key,
            "count": len(items),
            "products": [p.brief() for p in items[:limit]],
        }

    if name == "inventory_summary":
        return facts.summary()

    if name == "simulate_financial_impact":
        res = resolver.resolve(str(args.get("product", "")))
        if res.status != "resolved":
            return {"status": res.status, "candidates": res.options()}
        p = res.product
        qty = max(0, int(args.get("qty", 0) or 0))
        action = str(args.get("action_type", "reorder")).lower()
        cost = round(p.cost_price * qty, 2)
        revenue = round(p.selling_price * qty, 2)
        if action == "clearance":
            revenue = round(revenue * 0.7, 2)
        return {
            "product": p.name,
            "action": action,
            "qty": qty,
            "cash_out": cost if action == "reorder" else 0.0,
            "revenue": 0.0 if action == "reorder" else revenue,
            "gross_margin": round(revenue - cost, 2),
            "margin_pct": round(((revenue - cost) / revenue * 100), 1) if revenue else 0.0,
            "days_of_cover_after": (
                round((p.quantity + qty) / p.daily_burn_rate, 1)
                if action == "reorder" and p.daily_burn_rate > 0
                else None
            ),
        }

    return {"error": f"unknown tool: {name}"}


# ---------------------------------------------------------------------------
# 1. Router
# ---------------------------------------------------------------------------

_ANALYTICS_PATTERNS = [
    r"\b(analyz|analys|forecast|predict|trend|report|summary|stats|metric|valuation|worth)\w*\b",
    r"\b(low stock|out of stock|stockout|dead ?stock|overstock|health audit|inventory audit|audit report|reorder list)\b",
    r"\b(top\s+\d+|highest\s+stock|best[\s-]?sell\w*|slow[\s-]?moving|fastest[\s-]?moving)\b",
    r"\b(show\s+(all|inventory|products|catalog|items))\b",
    r"\b(days? of (cover|supply)|runs? out|run out|what should i (buy|order))\b",
    r"\b((is|are)?n.?t selling|not selling|no movement|stagnant|obsolete)\b",
    r"\b(order log|audit log|ledger|transaction history|recent actions)\b",
    r"\b(how much .* worth|total value|inventory value|capital tied)\b",
]

_EXECUTION_PATTERNS = [
    r"\b(add|deduct|remove|reduce|increase|restock|received)\b.*\b\d+\b",
    r"\b\d+\b.*\b(add|deduct|remove|reduce|increase|restock|units?)\b",
    r"\b(update stock|create po|purchase order|transfer stock|set threshold|set alert|raise a po)\b",
    r"\b(reorder|order|move|audit)\b.*\b(units?|qty|quantity|pieces?)\b",
    r"\b(set|change)\b.*\b(threshold|minimum|min level|reorder point)\b",
    # Creating a product often carries no number at all, so the quantity-based
    # patterns above never fire for it.
    r"\b(add|create|register|make|new)\b.*\b(product|item|sku|article)\b",
    r"\b(add|create)\s+(a\s+)?new\b",
]

_CLASSIFY_PROMPT = (
    "Classify this inventory assistant request into exactly one intent.\n"
    "EXECUTION: the user wants to change data (stock levels, purchase orders, "
    "transfers, audits, thresholds).\n"
    "ANALYTICS: the user wants numbers, lists, reports, forecasts or "
    "recommendations derived from inventory data.\n"
    "KNOWLEDGE: general questions, advice, or anything else.\n"
    "Reply with one word: EXECUTION, ANALYTICS or KNOWLEDGE."
)

_route_cache: Dict[str, str] = {}
_ROUTE_CACHE_MAX = 500


async def _classify_with_llm(question: str) -> Tuple[str, str]:
    key = " ".join(question.lower().split())[:200]
    cached = _route_cache.get(key)
    if cached:
        return cached, "llm_cache"

    client = llm_factory.get_llm(llm_factory.ROUTER, temperature=0.0)
    if client is None:
        return "KNOWLEDGE", "default"

    try:
        response = await client.ainvoke(
            [SystemMessage(content=_CLASSIFY_PROMPT), HumanMessage(content=question)]
        )
        llm_factory.usage.record(llm_factory.ROUTER, response)
        text = str(getattr(response, "content", "")).upper()
        intent = next(
            (i for i in ("EXECUTION", "ANALYTICS", "KNOWLEDGE") if i in text),
            "KNOWLEDGE",
        )
    except Exception as exc:
        print(f"[router] classification failed: {exc}")
        return "KNOWLEDGE", "default"

    if len(_route_cache) >= _ROUTE_CACHE_MAX:
        _route_cache.clear()
    _route_cache[key] = intent
    return intent, "llm"


async def router_node(state: GraphState) -> GraphState:
    question = state.get("question", "")
    q = question.lower().strip()
    company_id = state.get("company_id", "default")
    session_id = state.get("session_id", "default")

    outstanding = pending_actions.get(company_id, session_id)
    if outstanding:
        # While a "which product did you mean?" question is open, the reply is
        # usually a bare barcode or name — which on its own looks like a lookup.
        # It has to reach the execution agent or the pending action is stranded.
        if outstanding.get("tool") in ("__clarify__", "__new_product__"):
            state["intent"] = "EXECUTION"
            state["route_source"] = "pending"
            return state
        # Otherwise a confirmation or cancellation only means anything against
        # a live preview.
        if is_confirmation(q) or is_cancellation(q):
            state["intent"] = "EXECUTION"
            state["route_source"] = "pending"
            return state

    # A bulk instruction ("restock everything that's low") carries no quantity
    # and no product name, so the execution patterns miss it and the analytics
    # patterns claim it — the user got a report back instead of the change they
    # asked for.
    if bulk.is_bulk_write(q):
        state["intent"] = "EXECUTION"
        state["route_source"] = "bulk"
        return state

    if any(re.search(p, q) for p in _EXECUTION_PATTERNS):
        state["intent"] = "EXECUTION"
        state["route_source"] = "regex"
        return state

    if any(re.search(p, q) for p in _ANALYTICS_PATTERNS):
        state["intent"] = "ANALYTICS"
        state["route_source"] = "regex"
        return state

    # Short pleasantries never need a model call.
    if len(q) < 4 or q in {"hi", "hey", "hello", "thanks", "thank you", "ok"}:
        state["intent"] = "KNOWLEDGE"
        state["route_source"] = "regex"
        return state

    intent, source = await _classify_with_llm(question)
    state["intent"] = intent
    state["route_source"] = source
    return state


# ---------------------------------------------------------------------------
# 2. Retrieve — build the fact context for this turn
# ---------------------------------------------------------------------------

def _workspace_block(facts: InventoryFacts) -> str:
    """How *this* company's data is set up.

    The agent used to see stock numbers and nothing else, so it invented shelf
    names, categories and units that no screen in the app would ever match, and
    it could not answer "how is my inventory organised?" at all. This is the
    vocabulary and the rules the rest of the app runs on.
    """
    s = facts.summary()
    lines = [f"WORKSPACE SETUP ({s['total_products']} products):"]

    locations = facts.known_locations
    if locations:
        lines.append(
            f"- Locations ({len(locations)}): "
            + ", ".join(locations[:20])
            + (" …" if len(locations) > 20 else "")
        )
    else:
        lines.append("- Locations: none configured yet.")

    categories = sorted({(p.category or "").strip() for p in facts.products} - {""})
    for c in facts.categories or []:
        name = str(c.get("name", "")).strip()
        if name and name not in categories:
            categories.append(name)
    if categories:
        lines.append(
            f"- Categories ({len(categories)}): "
            + ", ".join(categories[:20])
            + (" …" if len(categories) > 20 else "")
        )

    units = sorted({(p.unit or "").strip() for p in facts.products} - {""})
    if units:
        lines.append("- Units in use: " + ", ".join(units[:12]))

    vendors = sorted({(p.vendor_name or "").strip() for p in facts.products} - {""})
    if vendors:
        lines.append(
            f"- Suppliers ({len(vendors)}): "
            + ", ".join(vendors[:12])
            + (" …" if len(vendors) > 12 else "")
        )

    lines.append(
        "- 'Low stock' means quantity at or below that product's own threshold; "
        "'out of stock' means zero. Each product carries its own threshold."
    )
    lines.append(
        f"- Demand, burn rate and days of cover come from recorded stock "
        f"movements over the last {facts.window_days} days; "
        f"{s['history_coverage_pct']}% of products have any."
    )
    if s["held_units"]:
        lines.append(
            f"- {s['held_units']} units are held/reserved against open orders and "
            "are not freely available."
        )
    return "\n".join(lines)


async def retrieve_node(state: GraphState) -> GraphState:
    company_id = state.get("company_id", "default")
    question = state.get("question", "")
    intent = state.get("intent", "KNOWLEDGE")

    facts = state.get("facts") or await asyncio.to_thread(fact_store.get, company_id)
    state["facts"] = facts

    focus: List[ProductFact] = []
    blocks: List[str] = [facts.summary_line(), _workspace_block(facts)]

    provided = (state.get("provided_context") or "").strip()
    if provided and "[REAL_USER_CATALOG:" not in provided:
        blocks.append(f"CLIENT CONTEXT:\n{provided[:800]}")

    if intent == "EXECUTION":
        # The whole point: give the agent the exact SKUs this request is about,
        # with live numbers, so it never has to guess a barcode.
        # Hand the resolver the raw question. It strips command words itself
        # for name matching, but only after checking barcodes against the
        # untouched tokens — and `strip_command_words` removes every numeric
        # token, barcodes included. Pre-stripping made it impossible to
        # disambiguate duplicate names by barcode, which is the only thing that
        # tells them apart.
        if question.strip():
            resolution = _resolver(facts).resolve(question, limit=5)
            focus = [c.product for c in resolution.candidates]
            state["clarification_options"] = (
                resolution.options() if resolution.status == "ambiguous" else None
            )
        if not focus:
            focus = sorted(facts.products, key=lambda p: p.days_of_supply)[:8]
        blocks.append(
            "PRODUCTS MATCHING THIS REQUEST (use these exact names/barcodes):\n"
            + "\n".join(p.context_line() for p in focus[:MAX_CONTEXT_PRODUCTS])
        )
        # Creating or moving stock means choosing from the company's own
        # vocabulary — the setup block above lists it, and nothing outside it
        # is valid.
        blocks.append(
            "Locations, categories and units must come from WORKSPACE SETUP "
            "above, spelled exactly as listed. Never invent one."
        )

    elif intent == "ANALYTICS":
        priority = facts.needs_reorder[:10] + facts.dead_stock[:5]
        seen = set()
        focus = [p for p in priority if not (p.id in seen or seen.add(p.id))]
        if focus:
            blocks.append(
                "PRIORITY ITEMS:\n"
                + "\n".join(p.context_line() for p in focus[:MAX_CONTEXT_PRODUCTS])
            )

    else:  # KNOWLEDGE
        if question.strip():
            candidates = _resolver(facts).search(question, limit=5)
            focus = [c.product for c in candidates if c.score >= 0.5][:5]
        if focus:
            blocks.append(
                "RELEVANT PRODUCTS:\n" + "\n".join(p.context_line() for p in focus)
            )

    state["focus"] = focus
    state["context_block"] = "\n\n".join(b for b in blocks if b)
    return state


# ---------------------------------------------------------------------------
# 3. Execution agent
# ---------------------------------------------------------------------------

_PREVIEW_LABELS = {
    "create_product": "Add new product",
    "update_stock": "Update stock",
    "create_purchase_order": "Create purchase order",
    "transfer_stock": "Transfer stock",
    "audit_inventory": "Audit stock count",
    "set_reorder_threshold": "Change reorder threshold",
}


def _build_new_product_preview(args: Dict[str, Any], facts: InventoryFacts) -> str:
    """Show exactly what will be created, so nothing is silently assumed."""
    rows = [
        f"| **Name** | **{args.get('name', '')}** |",
        f"| **Action** | **Add new product** |",
        f"| **Opening stock** | **{args.get('quantity', 0)} {args.get('unit') or 'pcs'}** |",
        f"| **Location** | {args.get('location') or '-'} |",
    ]
    for label, key in (
        ("Barcode", "barcode"), ("Category", "category_name"), ("Brand", "brand"),
        ("Size", "size"), ("Supplier", "vendor_name"),
    ):
        if args.get(key):
            rows.append(f"| **{label}** | {args[key]} |")
    if args.get("cost_price"):
        rows.append(f"| **Cost price** | {float(args['cost_price']):,.2f} |")
    if args.get("selling_price"):
        rows.append(f"| **Selling price** | {float(args['selling_price']):,.2f} |")
    rows.append(f"| **Low-stock alert** | {args.get('low_stock_threshold', 10)} |")

    blank = [
        label for label, key in
        (("category", "category_name"), ("cost price", "cost_price"),
         ("selling price", "selling_price"), ("barcode", "barcode"))
        if not args.get(key)
    ]
    table = "\n".join(["| Detail | Information |", "| :--- | :--- |"] + rows)
    note = ""
    if blank:
        note = (
            "\n\n> Left blank: " + ", ".join(blank) +
            ". You can add them now or edit the product later."
        )
    return (
        "### Confirm new product\n\nThis will add a product to your catalog.\n\n"
        + table + note + "\n\nReply **Confirm** to create it, or **Cancel** to discard."
    )


def _build_preview(tool: str, product: ProductFact, args: Dict[str, Any]) -> str:
    rows = [
        f"| **Product** | **{product.name}** |",
        f"| **Barcode** | `{product.barcode}` |",
        f"| **Action** | **{_PREVIEW_LABELS.get(tool, tool)}** |",
    ]

    if tool == "update_stock":
        delta = int(args.get("qty_change", 0))
        projected = max(0, product.quantity + delta)
        rows += [
            f"| **Current stock** | {product.quantity} units |",
            f"| **Change** | **{delta:+d} units** |",
            f"| **Projected stock** | **{projected} units** |",
        ]
        target = (args.get("location") or product.location or "").strip()
        if target:
            at = product.location_quantities.get(target)
            rows.append(
                f"| **Location** | {target}"
                + (f" ({at} units there now)" if at is not None else "")
                + " |"
            )
        if product.held_quantity:
            rows.append(f"| **Held / reserved** | {product.held_quantity} units |")
        if delta < 0 and product.available_qty < abs(delta):
            rows.append(
                f"| **Warning** | only {product.available_qty} units are unreserved |"
            )
    elif tool == "create_purchase_order":
        qty = int(args.get("reorder_qty", 0))
        rows += [
            f"| **Order quantity** | **{qty} units** |",
            f"| **Unit cost** | {product.cost_price:,.2f} |",
            f"| **Total cost** | **{qty * product.cost_price:,.2f}** |",
            f"| **Supplier** | {args.get('supplier_name') or product.vendor_name or 'Default Supplier'} |",
            f"| **Lead time** | {product.lead_time_days} days |",
        ]
    elif tool == "transfer_stock":
        rows += [
            f"| **From** | {args.get('from_location', '-')} |",
            f"| **To** | {args.get('to_location', '-')} |",
            f"| **Quantity** | **{args.get('qty', 0)} units** |",
        ]
    elif tool == "audit_inventory":
        counted = int(args.get("actual_stock", 0))
        rows += [
            f"| **System stock** | {product.quantity} units |",
            f"| **Counted** | **{counted} units** |",
            f"| **Discrepancy** | **{counted - product.quantity:+d} units** |",
        ]
    elif tool == "set_reorder_threshold":
        rows += [
            f"| **Current threshold** | {product.min_threshold} |",
            f"| **New threshold** | **{args.get('new_threshold', 0)}** |",
        ]

    table = "\n".join(["| Detail | Information |", "| :--- | :--- |"] + rows)
    return (
        "### Confirm this change\n\n"
        "This will write to your live inventory.\n\n"
        + table
        + "\n\nReply **Confirm** to apply, or **Cancel** to discard."
    )


_QTY_RE = re.compile(r"\b(\d{1,5})\b")


def _stock_intent(text: str) -> Optional[Tuple[str, Dict[str, Any]]]:
    """Recover the action a message asked for, ignoring which product it named.

    Used when the user answers a "which one did you mean?" question: the reply
    is just a barcode, so the quantity and direction have to come from the
    original request or the intent is silently lost.
    """
    q = (text or "").lower()
    numbers = [int(n) for n in _QTY_RE.findall(q) if len(n) < 6]
    qty = numbers[0] if numbers else None
    if qty is None:
        return None

    if any(w in q for w in ("purchase order", "create po", "raise a po", "reorder", "order")):
        return "create_purchase_order", {"reorder_qty": qty, "supplier_name": ""}
    if any(w in q for w in ("deduct", "remove", "reduce", "subtract", "sold", "damaged", "minus")):
        return "update_stock", {"qty_change": -qty, "reason": "AI adjustment"}
    if any(w in q for w in ("add", "increase", "restock", "received", "plus")):
        return "update_stock", {"qty_change": qty, "reason": "AI adjustment"}
    return None


_NEW_PRODUCT_RE = re.compile(
    r"\b(?:add|create|register|make)\b[^.]*?\bnew\b|\b(?:add|create|register)\s+(?:a\s+)?(?:new\s+)?(?:product|item|sku)\b",
    re.IGNORECASE,
)
_NAME_RE = re.compile(
    # "add a new product called X" puts two keywords in front of the name, so
    # the lead-in is consumed explicitly rather than captured with it.
    r"(?:called|named|name[d:]?|product|item|sku)\s+"
    r"(?:called\s+|named\s+)?[\"']?([A-Za-z0-9][^\"'\n,.]{2,60})[\"']?",
    re.IGNORECASE,
)
_MONEY_RE = re.compile(
    r"\b(cost|buy|purchase|sell(?:ing)?|retail|mrp|price)\w*\s*(?:price\s*)?(?:is|=|:|at)?\s*"
    r"(?:rs\.?|inr|₹|\$)?\s*(\d+(?:\.\d+)?)",
    re.IGNORECASE,
)
_UNIT_WORDS = ("pcs", "piece", "box", "tube", "bottle", "strip", "pack", "vial", "kg", "litre", "liter")


def _extract_product_fields(
    text: str, facts: InventoryFacts, have_name: bool
) -> Dict[str, Any]:
    """Pull whatever product details a message contains.

    Collecting a new product is driven from here rather than left to the model.
    Asked to gather fields conversationally the model tends to ask its own
    questions without ever calling the tool, so the draft is never recorded and
    every answer is read as a fresh, contextless request.
    """
    found: Dict[str, Any] = {}
    raw = text or ""
    low = raw.lower()

    if not have_name:
        m = _NAME_RE.search(raw)
        if m:
            name = m.group(1).strip().rstrip(" .,")
            # Drop a trailing quantity phrase caught by the greedy name match.
            name = re.sub(r"\s+\d+\s*(?:units?|pcs|nos)?$", "", name, flags=re.I).strip()
            if len(name) > 2:
                found["name"] = name

    qty = re.search(r"\b(\d{1,6})\s*(?:units?|pcs|nos|pieces?)\b", low) or re.search(
        r"^\s*(\d{1,6})\s*$", low
    )
    if qty:
        found["quantity"] = int(qty.group(1))

    matched_location = next(
        (loc for loc in facts.known_locations if loc.lower() in low), None
    )
    if matched_location:
        found["location"] = matched_location
    else:
        # Remember what they *tried* to say, so an unrecognised shelf can be
        # named back to them instead of silently repeating the question.
        guess = re.search(r"\b(?:in|at|to|on)\s+([A-Za-z0-9][\w .\-/]{1,30})", raw)
        if guess:
            found["_location_guess"] = guess.group(1).strip().rstrip(" .")
        elif 0 < len(raw.strip()) <= 30 and not re.fullmatch(r"[\d\s]+", raw.strip()):
            found["_location_guess"] = raw.strip()

    for cat in facts.categories:
        if cat["name"].lower() in low:
            found["category_name"] = cat["name"]
            found["category_id"] = cat["id"]
            break

    for kind, amount in _MONEY_RE.findall(raw):
        key = "cost_price" if kind.lower() in ("cost", "buy", "purchase") else "selling_price"
        found.setdefault(key, float(amount))

    for u in _UNIT_WORDS:
        if re.search(rf"\b{u}e?s?\b", low):
            found["unit"] = u
            break

    bc = re.search(r"\b(\d{8,14})\b", low)
    if bc:
        found["barcode"] = bc.group(1)

    return found


def _vet_new_product(args: Dict[str, Any], facts: InventoryFacts) -> Tuple[str, bool]:
    """Check a proposed product against the company's own vocabulary.

    Returns (message, ready_to_preview). Missing or unrecognised values produce
    a question rather than a guess: a made-up shelf or category creates a
    product that the app's own filters cannot find afterwards.
    """
    name = str(args.get("name", "")).strip()
    if not name:
        return "What should the product be called?", False

    # Guard against creating a second copy of something that exists.
    existing = _resolver(facts).resolve(name, limit=3)
    if existing.status in ("resolved", "ambiguous"):
        close = existing.candidates[0]
        if close.score >= 0.9:
            return (
                f"**{close.name}** (`{close.barcode}`) is already in your catalog with "
                f"{getattr(close.product, 'quantity', 0)} units. Did you want to add stock "
                f"to it instead? If this really is a different product, give me a "
                f"barcode or a more specific name.",
                False,
            )

    try:
        qty = int(args.get("quantity"))
    except (TypeError, ValueError):
        return f"How many units of **{name}** are you starting with?", False
    if qty < 0:
        return "Opening stock can't be negative.", False

    known = facts.known_locations
    location = str(args.get("location", "")).strip()
    if not location:
        rejected = str(args.pop("_location_guess", "")).strip()
        if rejected and known:
            listed = ", ".join(f"**{loc}**" for loc in known[:12])
            more = f" (+{len(known) - 12} more)" if len(known) > 12 else ""
            return (
                f"I don't have a location called \"{rejected}\". "
                f"Your locations are: {listed}{more}. Which one should it go to?",
                False,
            )
        if known:
            listed = ", ".join(f"**{loc}**" for loc in known[:12])
            more = f" (+{len(known) - 12} more)" if len(known) > 12 else ""
            return (
                f"Where should the {qty} units of **{name}** be stored? "
                f"Your locations are: {listed}{more}.",
                False,
            )
        return f"Where should the {qty} units of **{name}** be stored?", False

    if known:
        match = next((l for l in known if l.lower() == location.lower()), None)
        if match is None:
            listed = ", ".join(f"**{loc}**" for loc in known[:12])
            return (
                f"I don't recognise the location \"{location}\". "
                f"Your locations are: {listed}. Which should it go to?",
                False,
            )
        args["location"] = match

    # Snap the category to one that already exists so the app's filters work.
    wanted = str(args.get("category_name", "")).strip()
    if wanted and facts.categories:
        cat = facts.category_by_name(wanted)
        if cat is None:
            names = ", ".join(f"**{c['name']}**" for c in facts.categories[:12])
            return (
                f"There's no **{wanted}** category. Your categories are: {names}. "
                f"Which one fits, or shall I leave it uncategorised?",
                False,
            )
        args["category_name"] = cat["name"]
        args["category_id"] = cat["id"]

    args.pop("_location_guess", None)
    return _build_new_product_preview(args, facts), True


# ---------------------------------------------------------------------------
# Bulk (multi-product) requests
# ---------------------------------------------------------------------------

def _bulk_from_tool_args(args: Dict[str, Any], facts: InventoryFacts):
    """Turn a `bulk_action` tool call into a resolved plan, or None."""
    operation = str(args.get("operation", "")).strip().lower()
    mapped = BULK_OPERATIONS.get(operation)
    if mapped is None:
        return None
    tool, mode = mapped

    selector = bulk.selector_for_key(str(args.get("selector", "")), facts)
    if selector is None:
        return None

    try:
        qty = int(args.get("qty") or 0)
    except (TypeError, ValueError):
        qty = 0

    if tool == "update_stock" and mode == "fixed":
        if qty <= 0:
            return None
        delta = -qty if operation == "deduct_stock" else qty
        call_args: Dict[str, Any] = {
            "qty_change": delta,
            "reason": "Bulk adjustment via Ask AI",
        }
    elif tool == "update_stock":
        call_args = {"reason": "Bulk top-up to threshold via Ask AI"}
    elif tool == "create_purchase_order":
        if qty > 0:
            mode = "fixed"
            call_args = {"reorder_qty": qty, "supplier_name": ""}
        else:
            call_args = {"supplier_name": ""}
    elif tool == "set_reorder_threshold":
        if qty <= 0:
            return None
        call_args = {"new_threshold": qty}
    else:  # audit_inventory
        call_args = {"actual_stock": max(0, qty), "notes": "Bulk audit via Ask AI"}

    return bulk.build(tool, selector, facts, call_args, mode)


def _bulk_response(
    plan,
    facts: InventoryFacts,
    state: GraphState,
    company_id: str,
    session_id: str,
) -> GraphState:
    """Preview a bulk plan, or explain that nothing qualifies.

    An empty selection is a real answer. Letting it fall through to the model
    is how "add 10 to everything low" ended up creating a product called
    *pieces* when nothing was low.
    """
    if not plan.targets:
        pending_actions.clear(company_id, session_id)
        state["generation"] = bulk.empty_message(plan, facts)
        state["pending_action"] = None
        state["response_kind"] = "prose"
        state["executed_actions"] = []
        state["answered_by"] = "deterministic"
        state["llm_calls"] = 0
        return state

    action = plan.to_action()
    pending_actions.put(company_id, session_id, action)
    state["pending_action"] = action
    state["generation"] = bulk.preview(plan, facts)
    state["response_kind"] = "bulk_preview"
    state["items"] = action["targets"]
    state["executed_actions"] = []
    state["answered_by"] = "deterministic"
    state["llm_calls"] = 0
    return state


def _guardrail_check(tool: str, product: ProductFact, args: Dict[str, Any]):
    guardrails = InventoryGuardrails()
    if tool == "update_stock":
        new_stock = product.quantity + int(args.get("qty_change", 0))
        return guardrails.validate_action(
            "update_stock",
            {"new_stock": new_stock},
            {"stock": product.quantity, "cost_price": product.cost_price},
        )
    if tool == "create_purchase_order":
        return guardrails.validate_action(
            "create_reorder_po",
            {"quantity": int(args.get("reorder_qty", 0)), "cost_price": product.cost_price},
            {"stock": product.quantity, "cost_price": product.cost_price},
        )
    return None


def _apply_single(
    tool: str, product: ProductFact, args: Dict[str, Any], company_id: str
) -> Dict[str, Any]:
    """Perform one write. Shared by the single-product path and by bulk."""
    if tool == "update_stock":
        return writes.update_stock(
            product,
            int(args["qty_change"]),
            args.get("reason", "AI adjustment"),
            company_id,
            location=args.get("location") or None,
        )
    if tool == "create_purchase_order":
        return writes.create_purchase_order(
            product, int(args["reorder_qty"]), args.get("supplier_name", ""), company_id
        )
    if tool == "transfer_stock":
        return writes.transfer_stock(
            product, args["from_location"], args["to_location"], int(args["qty"]), company_id
        )
    if tool == "audit_inventory":
        return writes.audit_inventory(
            product, int(args["actual_stock"]), args.get("notes", "Physical audit"), company_id
        )
    if tool == "set_reorder_threshold":
        return writes.set_min_threshold(product, int(args["new_threshold"]), company_id)
    return {"success": False, "error": f"unknown action {tool}"}


def _execute_pending(
    action: Dict[str, Any],
    facts: InventoryFacts,
    company_id: str,
    permissions=None,
) -> Tuple[str, Dict[str, Any]]:
    """Run a previously previewed action against fresh facts.

    The permission check lives here rather than at preview time because this is
    the single choke point every chat-driven write passes through — a refusal
    here cannot be routed around by a differently-worded request.
    """
    tool = action["tool"]
    args = action["args"]

    # A bulk action is many writes of one kind; it is checked, and reported,
    # against that kind.
    checked_tool = action.get("inner_tool", tool) if tool == "__bulk__" else tool

    if not may_run_tool(checked_tool, permissions):
        needed = permission_for_tool(checked_tool)
        return (
            "You don't have permission to make that change, so I've left "
            f"everything as it was. Ask an admin for the **{needed}** "
            "permission if you need it.",
            {
                "tool": tool,
                "result": {"success": False, "error": "permission_denied"},
            },
        )

    if tool == "__bulk__":
        return bulk.execute(
            action,
            facts,
            company_id,
            lambda inner, product, call_args: _apply_single(
                inner, product, call_args, company_id
            ),
        )

    if tool == "create_product":
        result = writes.create_product(company_id=company_id, **args)
        if not result.get("success"):
            return (
                f"I couldn't create that product: {result.get('error', 'unknown error')}.",
                {"tool": tool, "result": result},
            )
        where = f" at {result['location']}" if result.get("location") else ""
        return (
            f"Added **{result['product_name']}** to your catalog with "
            f"**{result['quantity']} units**{where}.",
            {"tool": tool, "result": result},
        )

    product = facts.lookup(action["barcode"]) or facts.by_id(action.get("product_id", ""))
    if product is None:
        return (
            f"**{action.get('product_name', 'That product')}** is no longer in your "
            f"catalog, so I didn't apply the change.",
            {"tool": tool, "result": {"success": False, "error": "product not found"}},
        )

    result = _apply_single(tool, product, args, company_id)

    if not result.get("success"):
        return (
            f"I couldn't apply that change: {result.get('error', 'unknown error')}.",
            {"tool": tool, "result": result},
        )

    if tool == "update_stock":
        message = (
            f"Done. **{product.name}** is now at **{result['new_stock']} units** "
            f"(was {result['old_stock']}, {result['qty_change']:+d})."
        )
    elif tool == "create_purchase_order":
        message = (
            f"Purchase order **{result['po_id']}** drafted: **{result['reorder_qty']} units** "
            f"of **{product.name}** from {result['supplier']}, "
            f"total **{result['total_cost']:,.2f}**."
        )
    elif tool == "transfer_stock":
        message = (
            f"Moved **{result['qty']} units** of **{product.name}** from "
            f"{result['from_location']} to {result['to_location']}."
        )
    elif tool == "audit_inventory":
        message = (
            f"Audit recorded for **{product.name}**: set to "
            f"**{result['actual_stock']} units** ({result['discrepancy']:+d} vs system)."
        )
    else:
        message = (
            f"Reorder threshold for **{product.name}** is now "
            f"**{result['new_threshold']}** (was {result['old_threshold']})."
        )

    return message, {"tool": tool, "result": result}


async def execution_agent_node(state: GraphState) -> GraphState:
    question = state.get("question", "")
    company_id = state.get("company_id", "default")
    session_id = state.get("session_id", "default")
    facts: InventoryFacts = state["facts"]
    executed: List[Dict[str, Any]] = []

    # --- 1. Resolve an outstanding confirmation without touching a model ---
    pending = pending_actions.get(company_id, session_id)

    # The user is answering "which one did you mean?". Their reply is a barcode
    # or a name and carries no quantity, so the action has to be recovered from
    # the request that triggered the question — otherwise picking a product
    # just prints its details and the original intent is quietly dropped.
    # Collecting the fields for a new product takes several turns. The draft is
    # kept so each answer adds to it, instead of every reply being read as a
    # fresh, contextless request.
    draft_open = bool(pending and pending.get("tool") == "__new_product__")
    if draft_open and is_cancellation(question):
        pending_actions.clear(company_id, session_id)
        state["generation"] = "Cancelled — no product was created."
        state["executed_actions"] = []
        state["response_kind"] = "prose"
        state["answered_by"] = "pending"
        return state

    # --- 1b. A request about a *group* of products, before anything reads the
    # sentence as one product's name ---
    #
    # "add 10 pieces to all low stock items" names no product at all. The
    # resolver used to reduce it to the token "low", match nothing, and the
    # model then reached for create_product — which asked for a location and
    # created a product called "pieces". A selector is resolved from the
    # snapshot here instead, and the user confirms the full list.
    if not (pending and pending.get("tool") == "__clarify__"):
        plan = bulk.parse(question, facts)
        if plan is not None:
            if draft_open:
                # The user has moved on from the half-finished product.
                pending_actions.clear(company_id, session_id)
            return _bulk_response(plan, facts, state, company_id, session_id)

    if draft_open or _NEW_PRODUCT_RE.search(question):
        draft = dict((pending or {}).get("draft") or {})
        draft.update(
            _extract_product_fields(question, facts, have_name=bool(draft.get("name")))
        )
        message, ready = _vet_new_product(draft, facts)
        if ready:
            pending_actions.clear(company_id, session_id)
            action = {
                "tool": "create_product",
                "args": draft,
                "barcode": draft.get("barcode", ""),
                "product_id": "",
                "product_name": draft.get("name", ""),
            }
            pending_actions.put(company_id, session_id, action)
            state["pending_action"] = action
            state["response_kind"] = "preview"
        else:
            pending_actions.put(
                company_id, session_id, {"tool": "__new_product__", "draft": draft}
            )
            state["response_kind"] = "clarification"
        state["generation"] = message
        state["executed_actions"] = []
        state["answered_by"] = "deterministic"
        state["llm_calls"] = 0
        return state

    if pending and pending.get("tool") == "__clarify__":
        if is_cancellation(question):
            pending_actions.clear(company_id, session_id)
            state["generation"] = "Cancelled — nothing was changed."
            state["executed_actions"] = []
            state["response_kind"] = "prose"
            state["answered_by"] = "pending"
            return state

        chosen = _resolver(facts).resolve(question, limit=5)
        intent = _stock_intent(pending.get("original_question", ""))
        if chosen.status == "resolved" and intent:
            pending_actions.clear(company_id, session_id)
            tool, args = intent
            product = chosen.product
            verdict = _guardrail_check(tool, product, args)
            if verdict is not None and not verdict.passed:
                state["generation"] = "I stopped that action: " + " ".join(verdict.reasons)
                state["executed_actions"] = []
                state["response_kind"] = "prose"
                state["answered_by"] = "deterministic"
                return state
            action = {
                "tool": tool,
                "args": args,
                "barcode": product.barcode,
                "product_id": product.id,
                "product_name": product.name,
            }
            pending_actions.put(company_id, session_id, action)
            state["pending_action"] = action
            state["generation"] = _build_preview(tool, product, args)
            state["executed_actions"] = []
            state["response_kind"] = "preview"
            state["answered_by"] = "deterministic"
            state["llm_calls"] = 0
            return state
        pending = None  # not an answer to the question; treat normally

    if pending:
        if is_cancellation(question):
            pending_actions.clear(company_id, session_id)
            state["generation"] = "Cancelled — nothing was changed."
            state["executed_actions"] = []
            state["answered_by"] = "pending"
            state["response_kind"] = "prose"
            return state
        if is_confirmation(question):
            pending_actions.clear(company_id, session_id)
            fresh = await asyncio.to_thread(fact_store.get, company_id, True)
            state["facts"] = fresh
            message, record = await asyncio.to_thread(
                _execute_pending,
                pending,
                fresh,
                company_id,
                state.get("permissions"),
            )
            state["generation"] = message
            state["executed_actions"] = [record]
            state["answered_by"] = "pending"
            state["response_kind"] = "executed"
            return state

    # --- 2. Settle product identity before the model gets a say ---
    #
    # Catalogs legitimately contain several products with the same name, told
    # apart only by barcode. Left to itself the model improvises here: it writes
    # its own "which one did you mean?" prose (so the client gets no tappable
    # options and the user has to retype), and it has been observed replying
    # "not found" for a barcode it had just listed. The resolver already knows
    # the answer, so it decides — deterministically, for free, and in a shape
    # the UI can render.
    ambiguous = state.get("clarification_options")
    if ambiguous:
        resolution = _resolver(facts).resolve(question, limit=5)
        if resolution.status == "ambiguous":
            if _stock_intent(question):
                pending_actions.put(
                    company_id,
                    session_id,
                    {"tool": "__clarify__", "original_question": question},
                )
            state["generation"] = resolution.clarification()
            state["clarification_options"] = resolution.options()
            state["response_kind"] = "clarification"
            state["executed_actions"] = []
            state["answered_by"] = "deterministic"
            state["llm_calls"] = 0
            return state
        # The resolver settled it after all; drop the stale hint.
        state["clarification_options"] = None

    # --- 3. Ask the model which action to take ---
    client = llm_factory.get_llm(
        llm_factory.AGENT, temperature=0.0, tools=EXECUTION_TOOLS
    )
    if client is None:
        state["generation"] = (
            "I can't reach the reasoning model right now, so I won't guess at a "
            "stock change. Try again shortly, or make the change directly in the app."
        )
        state["executed_actions"] = []
        state["answered_by"] = "fallback"
        return state

    system = (
        f"You are the inventory execution agent for {business_context(state.get('business_type', 'retail_store'))}.\n\n"
        f"{state.get('context_block', '')}\n\n"
        "RULES:\n"
        "1. Use the exact product names and barcodes shown above. Never invent one.\n"
        "2. If the request is ambiguous between products, call search_products and "
        "then ask the user which they meant. Do not pick one yourself.\n"
        "3. If a quantity is missing, ask for it. Do not assume a number.\n"
        "4. Write actions are previewed for the user to confirm, so call the write "
        "tool once you know the product and quantity.\n"
        "5. Stock levels are already given above — do not call tools to re-read "
        "what you can see.\n"
        "6. To add a product that does not exist yet, call create_product. "
        "Search first — if something close already exists, adjust its stock "
        "instead of creating a duplicate.\n"
        "7. Never invent a location, category, price or barcode. Omit what you "
        "were not told and it will be asked for; a plausible-looking guess is "
        "worse than a question because it silently corrupts stock valuation.\n"
        "8. When a product holds stock in more than one location, pass the "
        "location on update_stock.\n"
        "9. Be brief and concrete."
    )

    draft = state.get("new_product_draft")
    if draft:
        system += (
            "\n\nYou are part-way through adding a new product. Collected so far: "
            + json.dumps(draft)
            + ". The user's message answers whichever field is still missing. "
            "Call create_product again with everything you now know — including "
            "the values already collected — and do not ask for what you already have."
        )

    messages: List[Any] = [SystemMessage(content=system)]
    messages.extend(sanitize_history(state.get("history")))
    messages.append(HumanMessage(content=question))

    generation = ""
    llm_calls = 0
    answered_by = "llm"

    for _ in range(MAX_TOOL_ITERATIONS):
        try:
            response = await stream_message(client, messages, llm_factory.AGENT)
            llm_calls += 1
        except Exception as exc:
            print(f"[execution] LLM call failed: {exc}")
            generation = (
                "I couldn't complete that action — the model call failed. "
                "Nothing was changed."
            )
            answered_by = "fallback"
            break

        messages.append(response)
        tool_calls = getattr(response, "tool_calls", None) or []

        if not tool_calls:
            generation = _text(response)
            break

        wrote_preview = False
        for call in tool_calls:
            name = call.get("name", "")
            args = call.get("args", {}) or {}
            call_id = call.get("id", "")

            if name not in WRITE_TOOL_NAMES:
                result = run_read_tool(name, args, facts)
                messages.append(ToolMessage(content=_json(result), tool_call_id=call_id))
                continue

            if name == "bulk_action":
                plan = _bulk_from_tool_args(args, facts)
                if plan is None:
                    messages.append(
                        ToolMessage(
                            content=_json({
                                "error": "unusable bulk request",
                                "valid_operations": sorted(BULK_OPERATIONS),
                                "valid_selectors": [s.key for s in bulk.SELECTORS]
                                + ["category:<name>", "location:<name>"],
                                "hint": "A quantity is required for add_stock, "
                                        "deduct_stock, set_threshold and audit.",
                            }),
                            tool_call_id=call_id,
                        )
                    )
                    continue
                _bulk_response(plan, facts, state, company_id, session_id)
                generation = state["generation"]
                # The answer is computed, but a model call got us here — say so,
                # or the telemetry hides a request the parser should have caught.
                answered_by = "llm"
                wrote_preview = True
                break

            # Creating a product has no existing SKU to resolve; it is checked
            # for completeness and for accidentally duplicating one instead.
            if name == "create_product":
                # A request naming a group of products is never a request to
                # create one. Without this the model answers "add 10 to every
                # low stock item" by inventing a product.
                selector = bulk.find_selector(question, facts)
                if selector is not None:
                    matched = selector.pick(facts)
                    generation = (
                        f"That's about **{len(matched)} {selector.label}**, not a new "
                        "product, so I haven't created anything. Tell me what to do to "
                        "them — for example *add 10 units to each*, *top them up to "
                        "their minimum*, or *order what each one needs*."
                        if matched
                        else bulk.selector_for_key(selector.key, facts).empty_message
                    )
                    state["response_kind"] = "clarification"
                    wrote_preview = True
                    break
                draft = dict(state.get("new_product_draft") or {})
                # Later turns supply one field at a time; keep everything
                # already gathered rather than starting over.
                draft.update({k: v for k, v in args.items() if v not in ("", None)})
                args = draft
                generation, ready = _vet_new_product(args, facts)
                if not ready:
                    pending_actions.put(
                        company_id, session_id,
                        {"tool": "__new_product__", "draft": args},
                    )
                if ready:
                    action = {"tool": name, "args": args, "barcode": args.get("barcode", ""),
                              "product_id": "", "product_name": args.get("name", "")}
                    pending_actions.put(company_id, session_id, action)
                    state["pending_action"] = action
                    state["response_kind"] = "preview"
                else:
                    state["response_kind"] = "clarification"
                wrote_preview = True
                break

            resolution = _resolver(facts).resolve(str(args.get("product", "")))
            if resolution.status == "ambiguous":
                generation = resolution.clarification()
                state["clarification_options"] = resolution.options()
                state["response_kind"] = "clarification"
                wrote_preview = True
                break
            if resolution.status == "not_found":
                generation = resolution.clarification()
                wrote_preview = True
                break

            product = resolution.product
            verdict = _guardrail_check(name, product, args)
            if verdict is not None and not verdict.passed:
                generation = (
                    "I stopped that action: " + " ".join(verdict.reasons)
                )
                wrote_preview = True
                break

            action = {
                "tool": name,
                "args": args,
                "barcode": product.barcode,
                "product_id": product.id,
                "product_name": product.name,
            }
            pending_actions.put(company_id, session_id, action)
            state["response_kind"] = "preview"
            generation = _build_preview(name, product, args)
            if verdict is not None and verdict.requires_human_approval and verdict.reasons:
                generation += "\n\n> Note: " + " ".join(verdict.reasons)
            state["pending_action"] = action
            wrote_preview = True
            break

        if wrote_preview:
            break

    if not generation:
        generation = (
            "I couldn't work out which product and quantity you meant. "
            "Try something like *Add 50 units of <product name>*."
        )
        answered_by = "fallback"

    state["generation"] = generation
    state["executed_actions"] = executed
    state["llm_calls"] = llm_calls
    state["answered_by"] = answered_by
    return state


def _real_data_answer(
    question: str, facts: InventoryFacts, company_id: str, state: GraphState
) -> str:
    """The closest answer that is built from the catalog rather than written.

    Used when a model answer has to be thrown away. Deterministic coverage is
    tried first so the user still gets what they asked for; the health summary
    is the floor, and it is always real.
    """
    try:
        instant = deterministic.answer(
            question, facts, company_id, state.get("business_type", "retail_store")
        )
        if instant:
            return instant.text
    except Exception as exc:
        print(f"[fallback] deterministic answer failed: {exc}")
    try:
        return (
            deterministic._summary(facts)
            + "\n\n> I dropped my first draft of this answer: it named products "
            "that aren't in your catalog. The figures above come straight from "
            "your live inventory."
        )
    except Exception:
        return ""


def _fact_check(
    answer: str,
    facts: InventoryFacts,
    where: str,
    fallback: Optional[Any] = None,
) -> str:
    """Correct claims the snapshot contradicts before the answer is sent.

    Quantities are repaired in place. Invented product names are not repairable
    — an answer listing "SKU 1, SKU 2" has no relationship to the catalog at
    all — so the whole answer is replaced with one built from real data.
    """
    try:
        corrected, issues = verify.check_answer(answer, facts)
    except Exception as exc:
        print(f"[{where}] fact check skipped: {exc}")
        return answer
    if issues:
        print(f"[{where}] corrected model output -> {verify.describe(issues)}")

    invented = [i for i in issues if i.kind == "placeholder"]
    if invented and fallback is not None:
        replacement = fallback()
        if replacement:
            print(
                f"[{where}] replaced an answer containing placeholder names: "
                + ", ".join(i.detail for i in invented[:5])
            )
            return replacement
    return corrected


def _text(response: Any) -> str:
    """Flatten a LangChain message content into plain text."""
    content = getattr(response, "content", response)
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, str):
                parts.append(part)
            elif isinstance(part, dict) and part.get("text"):
                parts.append(part["text"])
            elif getattr(part, "text", None):
                parts.append(part.text)
        return "".join(parts).strip()
    return str(content).strip()


# ---------------------------------------------------------------------------
# 4. Analytics agent
# ---------------------------------------------------------------------------

async def analytics_agent_node(state: GraphState) -> GraphState:
    question = state.get("question", "")
    company_id = state.get("company_id", "default")
    facts: InventoryFacts = state["facts"]

    instant = deterministic.answer(
        question, facts, company_id, state.get("business_type", "retail_store")
    )
    if instant:
        state["generation"] = instant.text + deterministic.stats_payload(facts)
        state["analytics_data"] = facts.summary()
        state["clarification_options"] = instant.clarification_options
        state["response_kind"] = instant.kind
        state["items"] = instant.items
        state["answered_by"] = "deterministic"
        state["llm_calls"] = 0
        return state

    client = llm_factory.get_llm(
        llm_factory.AGENT, temperature=0.1, tools=ANALYTICS_TOOLS
    )
    if client is None:
        state["generation"] = deterministic._summary(facts) + deterministic.stats_payload(facts)
        state["analytics_data"] = facts.summary()
        state["answered_by"] = "fallback"
        return state

    system = (
        f"You are the inventory analyst for {business_context(state.get('business_type', 'retail_store'))}.\n\n"
        f"{state.get('context_block', '')}\n\n"
        "RULES:\n"
        "1. Answer only from the data above or from tool results. Never estimate a "
        "number you were not given.\n"
        f"2. Demand figures come from the last {facts.window_days} days of recorded "
        "stock movements. If a product has no movement, say so rather than "
        "implying a forecast.\n"
        + (
            ""
            if facts.history_is_reliable
            else "2b. This company is barely recording stock movements. Absence of "
                 "movement means it is NOT BEING TRACKED, not that stock is not "
                 "selling. Never call it dead stock, never total up 'trapped "
                 "capital', and never name it as a business risk. If the question "
                 "needs demand data, say the transaction history is missing and "
                 "recommend recording stock movements.\n"
        ) +
        "3. Use a markdown table for any list of more than two items.\n"
        "4. Every product you name must come from the data above or from a tool "
        "result. If you need more rows, call list_products or search_products. "
        "Never write a placeholder like 'SKU 1', 'Product A' or "
        "'<product name>' — an invented row is worse than a short answer.\n"
        "5. Lead with the number that answers the question. At most three short "
        "paragraphs. No preamble, no disclaimers."
    )

    draft = state.get("new_product_draft")
    if draft:
        system += (
            "\n\nYou are part-way through adding a new product. Collected so far: "
            + json.dumps(draft)
            + ". The user's message answers whichever field is still missing. "
            "Call create_product again with everything you now know — including "
            "the values already collected — and do not ask for what you already have."
        )

    messages: List[Any] = [SystemMessage(content=system)]
    messages.extend(sanitize_history(state.get("history")))
    messages.append(HumanMessage(content=question))

    generation = ""
    llm_calls = 0
    answered_by = "llm"
    for _ in range(MAX_TOOL_ITERATIONS):
        try:
            response = await stream_message(client, messages, llm_factory.AGENT)
            llm_calls += 1
        except Exception as exc:
            print(f"[analytics] LLM call failed: {exc}")
            generation = deterministic._summary(facts)
            answered_by = "fallback"
            break

        messages.append(response)
        tool_calls = getattr(response, "tool_calls", None) or []
        if not tool_calls:
            generation = _text(response)
            break
        for call in tool_calls:
            result = run_read_tool(call.get("name", ""), call.get("args", {}) or {}, facts)
            messages.append(
                ToolMessage(content=_json(result), tool_call_id=call.get("id", ""))
            )

    if not generation:
        generation = deterministic._summary(facts)
        answered_by = "fallback"

    if answered_by == "llm":
        generation = _fact_check(
            generation,
            facts,
            "analytics",
            fallback=lambda: _real_data_answer(question, facts, company_id, state),
        )

    state["generation"] = generation + deterministic.stats_payload(facts)
    state["analytics_data"] = facts.summary()
    state["llm_calls"] = llm_calls
    state["answered_by"] = answered_by
    return state


# ---------------------------------------------------------------------------
# 5. Knowledge agent
# ---------------------------------------------------------------------------

async def knowledge_agent_node(state: GraphState) -> GraphState:
    question = state.get("question", "")
    company_id = state.get("company_id", "default")
    business_type = state.get("business_type", "retail_store")
    facts: InventoryFacts = state["facts"]

    instant = deterministic.answer(question, facts, company_id, business_type)
    if instant:
        state["generation"] = instant.text
        state["clarification_options"] = instant.clarification_options
        state["response_kind"] = instant.kind
        state["items"] = instant.items
        state["answered_by"] = "deterministic"
        state["llm_calls"] = 0
        return state

    # Read tools, not just a context block. Without them an advice question
    # about a product outside the five the resolver happened to surface had
    # nothing to work from, and the model filled the gap with "SKU 1, SKU 2".
    client = llm_factory.get_llm(
        llm_factory.AGENT, temperature=0.2, tools=READ_TOOLS
    )
    if client is None:
        state["generation"] = deterministic._summary(facts)
        state["answered_by"] = "fallback"
        return state

    system = (
        f"You are a direct, practical inventory advisor for {business_context(business_type)}.\n\n"
        f"{state.get('context_block', '')}\n\n"
        "RULES:\n"
        "1. Answer the question directly. No preamble.\n"
        "2. Ground advice in the real numbers above — name actual products.\n"
        "3. Every product you name must be one you have seen in this "
        "conversation's data. If you need products you haven't been shown, call "
        "search_products or list_products. Never write a placeholder like "
        "'SKU 1', 'Product A' or '<product name>' — say what is missing instead.\n"
        "4. At most four bullets or one short table.\n"
        "5. If the data doesn't support an answer, say what's missing instead of "
        "inventing it."
    )

    messages: List[Any] = [SystemMessage(content=system)]
    messages.extend(sanitize_history(state.get("history")))
    messages.append(HumanMessage(content=question))

    generation = ""
    llm_calls = 0
    answered_by = "llm"
    for _ in range(MAX_TOOL_ITERATIONS):
        try:
            response = await stream_message(client, messages, llm_factory.AGENT)
            llm_calls += 1
        except Exception as exc:
            print(f"[knowledge] LLM call failed: {exc}")
            generation = deterministic._summary(facts)
            answered_by = "fallback"
            break

        messages.append(response)
        tool_calls = getattr(response, "tool_calls", None) or []
        if not tool_calls:
            generation = _text(response)
            break
        for call in tool_calls:
            result = run_read_tool(call.get("name", ""), call.get("args", {}) or {}, facts)
            messages.append(
                ToolMessage(content=_json(result), tool_call_id=call.get("id", ""))
            )

    if not generation:
        generation = deterministic._summary(facts)
        answered_by = "fallback"

    if answered_by == "llm":
        generation = _fact_check(
            generation,
            facts,
            "knowledge",
            fallback=lambda: _real_data_answer(question, facts, company_id, state),
        )

    state["generation"] = generation
    state["llm_calls"] = llm_calls
    state["answered_by"] = answered_by
    return state


# Backwards-compatible aliases used by the existing test scripts.
retrieve = retrieve_node
generate = execution_agent_node
