"""
Deterministic answer bank — the cheapest and most accurate path in the system.

These are the questions people actually ask an inventory assistant, and every
one of them is a database query, not a reasoning problem. Answering them from
computed facts costs zero tokens, takes about a millisecond, and cannot
hallucinate a number.

Everything here reads from the fact layer, so the figures match the app's
Reports screen exactly.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from facts import InventoryFacts, ProductFact
from resolver import ProductResolver

MAX_TABLE_ROWS = 20


@dataclass
class DeterministicAnswer:
    """A complete answer produced without a model call.

    `clarification_options` is populated when the answer is a question about
    which product was meant, so the client can render them as tappable chips
    instead of making the user retype a name.

    `kind` tells the client which widget to render. Sniffing the prose for
    markdown tables works until the wording changes; declaring the shape here
    means the UI renders on structured data instead.
    """

    text: str
    clarification_options: Optional[List[Dict[str, Any]]] = None
    kind: str = "prose"
    # The rows behind a list answer, so the client can render tappable cards
    # instead of re-parsing the markdown table it was handed.
    items: Optional[List[Dict[str, Any]]] = None

    def __post_init__(self) -> None:
        if self.clarification_options:
            self.kind = "clarification"
        elif self.kind == "prose" and "\n| " in self.text:
            self.kind = "report"


def item_rows(products: List[ProductFact], limit: int = MAX_TABLE_ROWS) -> List[Dict[str, Any]]:
    """The structured form of a list answer, for the client's cards."""
    return [
        {
            "id": p.id,
            "barcode": p.barcode,
            "name": p.name,
            "stock": p.quantity,
            "available": p.available_qty,
            "threshold": p.min_threshold,
            "category": p.category,
            "unit": p.unit,
            "suggested_reorder_qty": p.suggested_reorder_qty,
            "days_of_cover": (
                None if p.days_of_supply >= 999 else round(p.days_of_supply, 1)
            ),
            "health": p.health,
        }
        for p in products[:limit]
    ]


def _money(value: float) -> str:
    return f"{value:,.2f}"


def _cover(p: ProductFact) -> str:
    if p.daily_burn_rate <= 0:
        return "no sales"
    if p.days_of_supply >= 999:
        return "-"
    return f"{p.days_of_supply:.0f}d"


def _health_label(health: str) -> str:
    return {
        "at_risk": "At Risk",
        "dead_stock": "Dead Stock",
        "no_history": "Not Tracked",
        "overstocked": "Overstocked",
        "optimal": "Healthy",
    }.get(health, health.title())


def stats_payload(facts: InventoryFacts) -> str:
    """The `[STATS: {...}]` block the Flutter client parses for its metric cards."""
    s = facts.summary()
    return "\n\n[STATS: " + json.dumps(
        {
            "total": s["total_products"],
            "low": s["low_stock_count"],
            "out": s["out_of_stock_count"],
            "total_value": s["total_inventory_value"],
            "dead_stock": s["dead_stock_count"],
            "untracked": s["untracked_count"],
            "autopilot_recommendations_count": s["reorder_count"],
        }
    ) + "]"


def _table(headers: List[str], rows: List[str]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "| " + " | ".join([":---"] * len(headers)) + " |"
    return "\n".join([head, sep] + rows)


def _no_history_note(facts: InventoryFacts) -> str:
    """Say plainly when the ledger cannot support demand-based conclusions."""
    if facts.history_is_reliable:
        return ""
    s = facts.summary()
    if s["history_coverage_pct"] == 0:
        detail = (
            f"No stock movements are recorded in the last {facts.window_days} days"
        )
    else:
        detail = (
            f"Only {s['history_coverage_pct']}% of your {s['total_products']} SKUs have "
            f"any recorded movement in the last {facts.window_days} days"
        )
    return (
        f"\n\n> **Demand figures unavailable.** {detail}, so burn rate, days of cover "
        f"and dead-stock analysis can't be calculated. This reflects missing "
        f"transaction records rather than products that aren't selling. Recording "
        f"stock-out movements as you sell will turn all of this on."
    )


# ---------------------------------------------------------------------------
# Individual answers
# ---------------------------------------------------------------------------

def _priority_purchase(facts: InventoryFacts) -> str:
    candidates = facts.needs_reorder
    if not candidates:
        candidates = sorted(facts.products, key=lambda p: p.days_of_supply)
    if not candidates:
        return "There are no products in your inventory yet."

    p = candidates[0]
    qty = p.suggested_reorder_qty or max(10, p.min_threshold * 2 - p.available_qty)
    if p.quantity <= 0:
        urgency = "CRITICAL — out of stock"
    elif p.days_of_supply < 7:
        urgency = f"CRITICAL — under a week of cover"
    elif p.is_low_stock:
        urgency = "HIGH — below safety threshold"
    else:
        urgency = "MEDIUM"

    rows = [
        f"| **Product** | **{p.name}** |",
        f"| **Barcode** | `{p.barcode}` |",
        f"| **Current stock** | **{p.quantity} units**"
        + (f" ({p.available_qty} available, {p.held_quantity} held)" if p.held_quantity else "")
        + " |",
        f"| **Daily burn rate** | {p.daily_burn_rate:.2f} units/day |",
        f"| **Days of cover** | {_cover(p)} |",
        f"| **Reorder point** | {p.reorder_point} units |",
        f"| **Suggested order** | **+{qty} units** |",
        f"| **Lead time** | {p.lead_time_days} days"
        + (f" ({p.vendor_name})" if p.vendor_name else "")
        + " |",
        f"| **Urgency** | **{urgency}** |",
    ]
    return (
        f"### Priority purchase\n\n"
        f"The single most urgent item to order right now:\n\n"
        + _table(["Detail", "Value"], rows)
        + f"\n\nReply **\"Order {qty} units of {p.name}\"** and I'll raise the purchase order."
        + _no_history_note(facts)
    )


def _reorder_list(facts: InventoryFacts) -> str:
    items = facts.needs_reorder
    if not items:
        return (
            "Nothing needs reordering right now — every product is above its "
            "reorder point once lead time and demand variability are accounted for."
            + _no_history_note(facts)
        )
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.available_qty}** | {p.reorder_point} | "
        f"{_cover(p)} | **+{p.suggested_reorder_qty}** |"
        for p in items[:MAX_TABLE_ROWS]
    ]
    extra = (
        f"\n\n_{len(items) - MAX_TABLE_ROWS} more below reorder point._"
        if len(items) > MAX_TABLE_ROWS
        else ""
    )
    return (
        f"**{len(items)} products** are at or below their reorder point "
        f"(demand over the last {facts.window_days} days + supplier lead time):\n\n"
        + _table(
            ["Product", "Barcode", "Available", "Reorder pt", "Cover", "Order"], rows
        )
        + extra
        + _no_history_note(facts)
    )


def _health_audit(facts: InventoryFacts) -> str:
    s = facts.summary()
    ranked = sorted(
        facts.products,
        key=lambda p: (
            {"at_risk": 0, "dead_stock": 1, "no_history": 2, "overstocked": 3, "optimal": 4}.get(p.health, 5),
            p.days_of_supply,
        ),
    )
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {p.min_threshold} | "
        f"{p.daily_burn_rate:.2f} | {_cover(p)} | {_health_label(p.health)} |"
        for p in ranked[:MAX_TABLE_ROWS]
    ]
    return (
        f"### Inventory health audit\n\n"
        f"- **{s['total_products']}** products, **{_money(s['total_inventory_value'])}** retail value\n"
        f"- **{s['at_risk_count']}** at risk (under 14 days of cover or out of stock)\n"
        + (
            f"- **{s['dead_stock_count']}** dead stock, tying up **{_money(s['dead_stock_value'])}** at cost\n"
            if facts.history_is_reliable
            else f"- **{s['untracked_count']}** with no movement recorded (demand not tracked)\n"
        )
        + f"- **{s['overstocked_count']}** overstocked (over 90 days of cover)\n"
        f"- **{s['reorder_count']}** below reorder point\n\n"
        f"#### Priority items\n\n"
        + _table(
            ["Product", "Barcode", "Stock", "Min", "Burn/day", "Cover", "Status"], rows
        )
        + _no_history_note(facts)
    )


def _low_stock(facts: InventoryFacts) -> str:
    combined = facts.out_of_stock + facts.low_stock
    if not combined:
        return "Every product is above its safety threshold — nothing is running low."
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {p.min_threshold} | "
        f"{_cover(p)} | {'Out of stock' if p.is_out_of_stock else 'Low stock'} |"
        for p in combined[:MAX_TABLE_ROWS]
    ]
    extra = (
        f"\n\n_{len(combined) - MAX_TABLE_ROWS} more not shown._"
        if len(combined) > MAX_TABLE_ROWS
        else ""
    )
    return (
        f"**{len(facts.out_of_stock)} out of stock**, **{len(facts.low_stock)} low**:\n\n"
        + _table(["Product", "Barcode", "Stock", "Min", "Cover", "Status"], rows)
        + extra
    )


def _dead_stock(facts: InventoryFacts) -> str:
    if not facts.history_is_reliable:
        s = facts.summary()
        return (
            f"I can't tell you what isn't selling yet.\n\n"
            f"**{s['untracked_count']} of your {s['total_products']} SKUs** have no stock "
            f"movement recorded in the last {facts.window_days} days. That means the "
            f"movements aren't being recorded — it is not evidence that those products "
            f"aren't selling, so I won't label them dead stock or tell you capital is "
            f"trapped in them.\n\n"
            f"Record stock-out transactions as you sell, and within a few weeks I can "
            f"show you real burn rates, days of cover, genuine dead stock, and "
            f"reorder points based on your actual demand."
        )

    items = sorted(facts.dead_stock, key=lambda p: -p.cost_value)
    if not items:
        return (
            f"No dead stock — every product has moved at least once in the last "
            f"{facts.window_days} days." + _no_history_note(facts)
        )
    tied = sum(p.cost_value for p in items)
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {_money(p.cost_value)} | "
        f"{p.days_since_last_sale if p.days_since_last_sale is not None else f'{facts.window_days}+'}d |"
        for p in items[:MAX_TABLE_ROWS]
    ]
    return (
        f"**{len(items)} products** haven't sold in {facts.window_days} days, "
        f"tying up **{_money(tied)}** of working capital:\n\n"
        + _table(["Product", "Barcode", "Stock", "Cost tied up", "Last sold"], rows)
        + "\n\nClearance-pricing the top few recovers cash fastest."
    )


def _overstocked(facts: InventoryFacts) -> str:
    items = sorted(facts.overstocked, key=lambda p: -p.days_of_supply)
    if not items:
        return "Nothing is significantly overstocked — no product holds more than 90 days of cover."
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {_cover(p)} | {_money(p.cost_value)} |"
        for p in items[:MAX_TABLE_ROWS]
    ]
    return (
        f"**{len(items)} products** hold more than 90 days of cover:\n\n"
        + _table(["Product", "Barcode", "Stock", "Cover", "Cost tied up"], rows)
    )


def _runs_out_first(facts: InventoryFacts) -> str:
    moving = [p for p in facts.products if p.daily_burn_rate > 0]
    if not moving:
        return (
            f"No stock-out movements are recorded in the last {facts.window_days} days, "
            f"so I can't project which product runs out first. Record stock-out "
            f"transactions and this becomes available immediately."
        )
    moving.sort(key=lambda p: p.days_of_supply)
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {p.daily_burn_rate:.2f} | "
        f"**{p.days_of_supply:.0f} days** | {p.lead_time_days}d |"
        for p in moving[:MAX_TABLE_ROWS]
    ]
    first = moving[0]
    warn = (
        f"\n\n**{first.name}** runs out in about **{first.days_of_supply:.0f} days**, "
        f"and its supplier needs **{first.lead_time_days} days** — "
        + (
            "you are already inside the lead time, so order today."
            if first.days_of_supply <= first.lead_time_days
            else f"order within {max(0, int(first.days_of_supply - first.lead_time_days))} days."
        )
    )
    return (
        "Projected stockouts, soonest first:\n\n"
        + _table(
            ["Product", "Barcode", "Stock", "Burn/day", "Runs out in", "Lead time"], rows
        )
        + warn
    )


def _valuation(facts: InventoryFacts) -> str:
    s = facts.summary()
    rows = [
        f"| Retail value | **{_money(s['total_inventory_value'])}** |",
        f"| Cost basis | **{_money(s['total_cost_value'])}** |",
        f"| Unrealised margin | **{_money(s['unrealized_margin'])}** |",
        *([f"| Dead stock at cost | **{_money(s['dead_stock_value'])}** |"]
          if facts.history_is_reliable else []),
        f"| Products | **{s['total_products']}** |",
    ]
    if s["held_units"]:
        rows.append(f"| Units held / reserved | **{s['held_units']}** |")
    return "### Inventory valuation\n\n" + _table(["Metric", "Amount"], rows)


def _summary(facts: InventoryFacts) -> str:
    s = facts.summary()
    rows = [
        f"| Products | **{s['total_products']}** |",
        f"| Low stock | **{s['low_stock_count']}** |",
        f"| Out of stock | **{s['out_of_stock_count']}** |",
        f"| At risk (<14d cover) | **{s['at_risk_count']}** |",
        (
            f"| Dead stock | **{s['dead_stock_count']}** |"
            if facts.history_is_reliable
            else f"| Movement not tracked | **{s['untracked_count']}** |"
        ),
        f"| Needs reorder | **{s['reorder_count']}** |",
        f"| Retail value | **{_money(s['total_inventory_value'])}** |",
        f"| Cost basis | **{_money(s['total_cost_value'])}** |",
    ]
    return (
        "### Inventory snapshot\n\n"
        + _table(["Metric", "Value"], rows)
        + _no_history_note(facts)
    )


def _all_products(facts: InventoryFacts) -> str:
    if not facts.products:
        return "There are no products in your inventory yet."
    items = sorted(facts.products, key=lambda p: p.name.lower())
    shown = items[:25]
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.quantity}** | {p.min_threshold} | "
        f"{p.category} | {_money(p.selling_price)} |"
        for p in shown
    ]
    note = f" (showing first 25)" if len(items) > 25 else ""
    return (
        f"**{len(items)} products**{note}:\n\n"
        + _table(["Product", "Barcode", "Stock", "Min", "Category", "Price"], rows)
    )


def _top_by_stock(facts: InventoryFacts, question: str) -> str:
    nums = re.findall(r"\b(\d+)\b", question)
    n = min(int(nums[0]), 25) if nums else 5
    items = sorted(facts.products, key=lambda p: -p.quantity)[:n]
    if not items:
        return "There are no products in your inventory yet."
    rows = [
        f"| **{p.name}** | **{p.quantity}** | {p.category} | {_money(p.stock_value)} |"
        for p in items
    ]
    return (
        f"**Top {len(items)} products by stock level:**\n\n"
        + _table(["Product", "Stock", "Category", "Stock value"], rows)
    )


def _best_sellers(facts: InventoryFacts, question: str) -> str:
    moving = [p for p in facts.products if p.units_out_window > 0]
    if not moving:
        return (
            f"No stock-out movements are recorded in the last {facts.window_days} days, "
            f"so I can't rank sellers yet."
        )
    nums = re.findall(r"\b(\d+)\b", question)
    n = min(int(nums[0]), 25) if nums else 10
    moving.sort(key=lambda p: -p.units_out_window)
    rows = [
        f"| **{p.name}** | `{p.barcode}` | **{p.units_out_window}** | "
        f"{p.daily_burn_rate:.2f} | **{p.quantity}** | {_cover(p)} |"
        for p in moving[:n]
    ]
    return (
        f"**Top {min(n, len(moving))} movers over the last {facts.window_days} days:**\n\n"
        + _table(
            ["Product", "Barcode", f"Sold ({facts.window_days}d)", "Burn/day", "Stock", "Cover"],
            rows,
        )
    )


def _product_detail(p: ProductFact, facts: InventoryFacts) -> str:
    rows = [f"| Stock | **{p.quantity} units** |"]
    if p.held_quantity:
        rows.append(f"| Available to sell | **{p.available_qty}** ({p.held_quantity} held) |")
    rows.append(f"| Safety threshold | {p.min_threshold} |")
    if p.daily_burn_rate > 0:
        rows.append(f"| Burn rate | {p.daily_burn_rate:.2f} units/day |")
        rows.append(f"| Days of cover | **{_cover(p)}** |")
        rows.append(f"| Sold ({facts.window_days}d) | {p.units_out_window} units |")
    else:
        rows.append(f"| Movement | no sales in {facts.window_days} days |")
    rows.append(f"| Status | **{_health_label(p.health)}** |")
    if p.selling_price:
        rows.append(f"| Price | {_money(p.selling_price)} |")
    if p.location:
        rows.append(f"| Location | {p.location} |")
    if p.needs_reorder:
        rows.append(f"| Reorder point | {p.reorder_point} units |")
        rows.append(f"| Suggested order | **+{p.suggested_reorder_qty} units** |")
    return f"**{p.name}** (`{p.barcode}`)\n\n" + _table(["Detail", "Value"], rows)


def _order_log(facts: InventoryFacts, company_id: str) -> Optional[str]:
    try:
        from inventory_db import db_instance

        ledger = db_instance._get_company(company_id).get("action_ledger", [])
    except Exception:
        ledger = []
    if not ledger:
        return "No AI-executed actions have been recorded yet for this company."

    rows = []
    for item in reversed(ledger[-15:]):
        ts = str(item.get("timestamp", "")).replace("T", " ")[:16]
        action = str(item.get("action", "action")).replace("_", " ").title()
        product = item.get("product_name") or item.get("barcode") or "-"
        if action == "Update Stock":
            detail = f"{item.get('old_stock')} to **{item.get('new_stock')}** ({item.get('qty_change', 0):+d})"
        elif action == "Create Purchase Order":
            detail = f"PO {item.get('po_id')} | {item.get('reorder_qty')} units | {_money(item.get('total_cost', 0))}"
        elif action == "Transfer Stock":
            detail = f"{item.get('qty')} units to {item.get('to_location')}"
        elif action == "Audit Inventory":
            detail = f"set to **{item.get('actual_stock')}** ({item.get('discrepancy', 0):+d})"
        elif action == "Set Min Threshold":
            detail = f"{item.get('old_threshold')} to **{item.get('new_threshold')}**"
        else:
            detail = str(item.get("details", "logged"))[:60]
        rows.append(f"| {ts} | **{action}** | {product} | {detail} |")

    return "### Recent AI action log\n\n" + _table(
        ["When", "Action", "Product", "Detail"], rows
    )


def _growth_plan(facts: InventoryFacts) -> str:
    s = facts.summary()
    risk = facts.needs_reorder
    dead = sorted(facts.dead_stock, key=lambda p: -p.cost_value)
    top_risk = risk[0].name if risk else "your at-risk SKUs"
    top_dead = dead[0].name if dead else "your slowest movers"

    second = (
        f"| **2. Free trapped capital** | **{_money(s['dead_stock_value'])}** sits in "
        f"**{s['dead_stock_count']}** non-moving SKUs — clear **{top_dead}** first | Direct cash recovery |"
        if facts.history_is_reliable
        else "| **2. Start recording stock movements** | Only a fraction of your SKUs have "
             "movement history, so demand, dead stock and reorder points can't be computed | "
             "Unlocks every other insight here |"
    )

    rows = [
        f"| **1. Close the stockout gap** | Reorder your **{len(risk)}** below-reorder-point items, starting with **{top_risk}** | Protects revenue you are currently losing |",
        second,
        f"| **3. Right-size the overstock** | **{s['overstocked_count']}** SKUs hold 90+ days of cover; cut their next order | Lower holding cost |",
        f"| **4. Tighten reorder points** | Set thresholds from real burn rate + lead time rather than flat numbers | Fewer emergency orders |",
        f"| **5. Bundle slow with fast** | Pair non-movers with your top sellers | Higher basket value |",
    ]
    return (
        f"Growth plan for your **{s['total_products']} SKUs** "
        f"(**{_money(s['total_inventory_value'])}** retail value), built from your actual numbers:\n\n"
        + _table(["Priority", "What to do", "Why"], rows)
        + _no_history_note(facts)
    )


def _setup_overview(facts: InventoryFacts) -> str:
    """What this workspace actually contains and how it is organised.

    "How is my inventory set up?" used to reach the model, which had no view of
    locations, categories or units and answered in generalities.
    """
    s = facts.summary()
    locations = facts.known_locations
    categories = sorted({(p.category or "").strip() for p in facts.products} - {""})
    for c in facts.categories or []:
        name = str(c.get("name", "")).strip()
        if name and name not in categories:
            categories.append(name)
    units = sorted({(p.unit or "").strip() for p in facts.products} - {""})
    vendors = sorted({(p.vendor_name or "").strip() for p in facts.products} - {""})
    multi = [p for p in facts.products if len(p.location_quantities or {}) > 1]

    def listed(values: List[str], limit: int = 12) -> str:
        if not values:
            return "_none configured_"
        shown = ", ".join(f"**{v}**" for v in values[:limit])
        return shown + (f" _+{len(values) - limit} more_" if len(values) > limit else "")

    rows = [
        f"| **Products** | {s['total_products']} |",
        f"| **Locations** | {listed(locations)} |",
        f"| **Categories** | {listed(categories)} |",
        f"| **Units** | {listed(units, 8)} |",
        f"| **Suppliers** | {listed(vendors, 8)} |",
        f"| **Stock held / reserved** | {s['held_units']} units |",
        f"| **Products in more than one location** | {len(multi)} |",
        f"| **Movement history** | {s['history_coverage_pct']}% of products, "
        f"last {facts.window_days} days |",
    ]

    detail = (
        "\n\n**How the numbers are decided**\n\n"
        "- **Low stock** is a product at or below *its own* threshold — each "
        "product carries one, so there is no single company-wide number.\n"
        "- **Out of stock** is zero on hand.\n"
        f"- **Burn rate, days of cover and dead stock** are derived from stock "
        f"movements recorded in the last {facts.window_days} days.\n"
        "- **Available** stock excludes units held against open orders.\n"
        "- **Value** uses selling price; **cost basis** uses cost price."
    )
    gaps = []
    if not locations:
        gaps.append("no locations are configured, so stock has nowhere to sit")
    if not categories:
        gaps.append("no categories are in use, so filters and reports can't group anything")
    if not vendors:
        gaps.append("no suppliers are set, so purchase orders fall back to a default")
    if s["history_coverage_pct"] == 0:
        gaps.append("no stock movements are recorded, so demand can't be calculated")
    gap_note = (
        "\n\n> **Worth fixing:** " + "; ".join(gaps) + "."
        if gaps else ""
    )

    return (
        "Here's how your workspace is set up.\n\n"
        + _table(["Setting", "Value"], rows)
        + detail
        + gap_note
    )


def _capabilities(business_type: str) -> str:
    biz = business_type.replace("_", " ").title()
    rows = [
        "| **Update stock** | *Add 50 units of Cannula 18G* |",
        "| **Change many at once** | *Add 10 units to every low stock item* |",
        "| **Top everything back up** | *Restock all low stock items to their minimum* |",
        "| **Raise a PO** | *Order 100 bandages* |",
        "| **Health audit** | *Run an inventory audit* |",
        "| **Reorder plan** | *What should I order next?* |",
        "| **Stockout risk** | *What runs out first?* |",
        "| **Dead stock** | *What isn't selling?* |",
        "| **Lookup** | *How many gauze pads do I have?* |",
        "| **Your setup** | *How is my inventory configured?* |",
    ]
    return (
        f"I'm **Ask AI**, your {biz} inventory assistant. I work from your live "
        f"stock and your actual transaction history.\n\n"
        + _table(["What I do", "Try saying"], rows)
    )


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_LOOKUP_RE = re.compile(
    r"(?:stock (?:of|for)|how (?:much|many)|quantity of|do i have|"
    r"check stock (?:of|for)?|level (?:of|for)|available)\s+(.+?)(?:\?|$|\s+left|\s+in stock)",
    re.IGNORECASE,
)


def _any(question: str, phrases: List[str]) -> bool:
    return any(phrase in question for phrase in phrases)


def answer(
    question: str,
    facts: InventoryFacts,
    company_id: str = "default",
    business_type: str = "retail_store",
) -> Optional[DeterministicAnswer]:
    """Return a complete answer, or None to let the LLM handle it."""
    q = (question or "").lower().strip()
    if not q:
        return None

    if _any(q, ["who are you", "what can you do", "tell me about yourself", "what are you"]) or q in {
        "hi", "hello", "hey", "yo", "hi!", "hello!",
    }:
        return DeterministicAnswer(_capabilities(business_type), kind='prose')

    if _any(q, [
        "exact one product", "one product", "exact product", "single product",
        "single item", "what to buy now", "should buy now", "top product to buy",
        "which product to buy", "exact item", "what should i buy", "most urgent",
        "highest priority", "priority purchase",
    ]):
        return DeterministicAnswer(_priority_purchase(facts))

    if _any(q, [
        "order next", "what to order", "reorder next", "what to buy",
        "reorder suggestion", "reorder list", "autopilot", "should i order",
        "purchase plan", "replenish",
    ]):
        return DeterministicAnswer(
            _reorder_list(facts), items=item_rows(facts.needs_reorder)
        )

    if _any(q, [
        "order log", "log table", "ledger", "transaction history", "po log",
        "order history", "action ledger", "audit log", "recent actions",
    ]):
        return DeterministicAnswer(_order_log(facts, company_id))

    if _any(q, [
        "inventory audit", "stock audit", "health audit", "audit report",
        "audit table", "inventory health", "health check", "full audit",
    ]):
        return DeterministicAnswer(_health_audit(facts))

    if _any(q, [
        "dead stock", "deadstock", "not selling", "slow moving", "slow-moving",
        "isn't selling", "stagnant", "obsolete stock", "no movement",
    ]):
        return DeterministicAnswer(
            _dead_stock(facts),
            kind="no_history" if not facts.history_is_reliable else "report",
            items=item_rows(facts.dead_stock) if facts.history_is_reliable else None,
        )

    if _any(q, ["overstock", "over stock", "too much stock", "excess stock", "excess inventory"]):
        return DeterministicAnswer(_overstocked(facts))

    if _any(q, [
        "runs out", "run out", "stockout risk", "stock out first", "days of cover",
        "days of supply", "when will i run out", "runway", "how long will",
    ]):
        return DeterministicAnswer(_runs_out_first(facts))

    if _any(q, [
        "best seller", "best selling", "top seller", "fastest moving",
        "most sold", "top movers", "what sells",
    ]):
        return DeterministicAnswer(_best_sellers(facts, q))

    if _any(q, [
        "low stock", "out of stock", "stock alert", "stockout list",
        "running low", "below threshold",
    ]):
        return DeterministicAnswer(
            _low_stock(facts),
            items=item_rows(facts.out_of_stock + facts.low_stock),
        )

    if _any(q, [
        "total value", "inventory value", "inventory worth", "how much worth",
        "stock worth", "portfolio value", "total cost", "valuation",
        "capital tied", "worth right now", "how much is my stock",
        "how much is my inventory",
    ]):
        return DeterministicAnswer(_valuation(facts))

    if _any(q, [
        "grow my business", "grow business", "growth strategy", "boost sales",
        "increase revenue", "grow revenue", "help me grow", "growth plan",
    ]):
        return DeterministicAnswer(_growth_plan(facts), kind='report')

    if _any(q, [
        "how is my inventory configured", "how is my inventory set up",
        "how is it configured", "how is this configured", "my setup",
        "workspace setup", "inventory setup", "how is my stock organised",
        "how is my stock organized", "what locations", "which locations",
        "my locations", "what categories", "which categories", "my categories",
        "what units", "which suppliers", "what suppliers", "my suppliers",
        "what data do you have", "what do you know about my inventory",
        "how do you decide", "how do you calculate", "what counts as low stock",
        "configuration",
    ]):
        return DeterministicAnswer(_setup_overview(facts), kind='report')

    if _any(q, ["summary", "snapshot", "stats", "metrics", "overview", "dashboard"]):
        return DeterministicAnswer(_summary(facts))

    if _any(q, [
        "show all", "all products", "product list", "inventory list", "full list",
        "list everything", "show inventory", "all items", "list products",
    ]):
        return DeterministicAnswer(_all_products(facts))

    if re.search(r"\b(top|highest|most)\b.*\b(stock|stocked|inventory|items|products)\b", q):
        return DeterministicAnswer(_top_by_stock(facts, q))

    # Single-product lookup, resolved properly rather than by substring.
    match = _LOOKUP_RE.search(q)
    if match:
        phrase = match.group(1).strip().rstrip("?. ")
        if phrase:
            resolution = ProductResolver(facts.products).resolve(phrase)
            if resolution.status == "resolved":
                return DeterministicAnswer(
                    _product_detail(resolution.product, facts), kind='product_detail'
                )
            if resolution.status == "ambiguous":
                # Hand the candidates back so the client can offer them as
                # tappable chips rather than making the user retype a name.
                return DeterministicAnswer(
                    resolution.clarification(), resolution.options()
                )

    return None
