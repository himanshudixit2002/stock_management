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

import deterministic
import llm as llm_factory
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
    """Change a product's stock level. Positive adds, negative deducts."""

    product: str = Field(description="Exact product name or barcode.")
    qty_change: int = Field(description="Units to add (positive) or deduct (negative).")
    reason: str = Field(default="AI adjustment", description="Why the stock changed.")


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


class set_reorder_threshold(BaseModel):
    """Change a product's low-stock safety threshold."""

    product: str = Field(description="Exact product name or barcode.")
    new_threshold: int = Field(description="New minimum threshold.")


READ_TOOLS = [
    search_products,
    get_product,
    list_products,
    inventory_summary,
    simulate_financial_impact,
]
WRITE_TOOLS = [
    update_stock,
    create_purchase_order,
    transfer_stock,
    audit_inventory,
    set_reorder_threshold,
]
EXECUTION_TOOLS = READ_TOOLS + WRITE_TOOLS
ANALYTICS_TOOLS = READ_TOOLS

WRITE_TOOL_NAMES = {t.__name__ for t in WRITE_TOOLS}


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
        if outstanding.get("tool") == "__clarify__":
            state["intent"] = "EXECUTION"
            state["route_source"] = "pending"
            return state
        # Otherwise a confirmation or cancellation only means anything against
        # a live preview.
        if is_confirmation(q) or is_cancellation(q):
            state["intent"] = "EXECUTION"
            state["route_source"] = "pending"
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

async def retrieve_node(state: GraphState) -> GraphState:
    company_id = state.get("company_id", "default")
    question = state.get("question", "")
    intent = state.get("intent", "KNOWLEDGE")

    facts = state.get("facts") or await asyncio.to_thread(fact_store.get, company_id)
    state["facts"] = facts

    focus: List[ProductFact] = []
    blocks: List[str] = [facts.summary_line()]

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
    "update_stock": "Update stock",
    "create_purchase_order": "Create purchase order",
    "transfer_stock": "Transfer stock",
    "audit_inventory": "Audit stock count",
    "set_reorder_threshold": "Change reorder threshold",
}


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


def _execute_pending(action: Dict[str, Any], facts: InventoryFacts, company_id: str) -> Tuple[str, Dict[str, Any]]:
    """Run a previously previewed action against fresh facts."""
    tool = action["tool"]
    args = action["args"]
    product = facts.lookup(action["barcode"]) or facts.by_id(action.get("product_id", ""))
    if product is None:
        return (
            f"**{action.get('product_name', 'That product')}** is no longer in your "
            f"catalog, so I didn't apply the change.",
            {"tool": tool, "result": {"success": False, "error": "product not found"}},
        )

    if tool == "update_stock":
        result = writes.update_stock(
            product, int(args["qty_change"]), args.get("reason", "AI adjustment"), company_id
        )
    elif tool == "create_purchase_order":
        result = writes.create_purchase_order(
            product, int(args["reorder_qty"]), args.get("supplier_name", ""), company_id
        )
    elif tool == "transfer_stock":
        result = writes.transfer_stock(
            product, args["from_location"], args["to_location"], int(args["qty"]), company_id
        )
    elif tool == "audit_inventory":
        result = writes.audit_inventory(
            product, int(args["actual_stock"]), args.get("notes", "Physical audit"), company_id
        )
    elif tool == "set_reorder_threshold":
        result = writes.set_min_threshold(product, int(args["new_threshold"]), company_id)
    else:
        result = {"success": False, "error": f"unknown action {tool}"}

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
                _execute_pending, pending, fresh, company_id
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
        "6. Be brief and concrete."
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
        "4. Lead with the number that answers the question. At most three short "
        "paragraphs. No preamble, no disclaimers."
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
        state["answered_by"] = "deterministic"
        state["llm_calls"] = 0
        return state

    client = llm_factory.get_llm(llm_factory.AGENT, temperature=0.2)
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
        "3. At most four bullets or one short table.\n"
        "4. If the data doesn't support an answer, say what's missing instead of "
        "inventing it."
    )

    messages: List[Any] = [SystemMessage(content=system)]
    messages.extend(sanitize_history(state.get("history")))
    messages.append(HumanMessage(content=question))

    try:
        response = await stream_message(client, messages, llm_factory.AGENT)
        state["generation"] = _text(response) or deterministic._summary(facts)
        state["llm_calls"] = 1
        state["answered_by"] = "llm"
    except Exception as exc:
        print(f"[knowledge] LLM call failed: {exc}")
        state["generation"] = deterministic._summary(facts)
        state["answered_by"] = "fallback"

    return state


# Backwards-compatible aliases used by the existing test scripts.
retrieve = retrieve_node
generate = execution_agent_node
