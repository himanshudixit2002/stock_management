"""Model Context Protocol server over the live inventory.

The Flutter app and the chat endpoint are two front doors onto the same fact
layer. This is a third, for MCP clients — Claude Desktop, an IDE, anything that
speaks the protocol — so a question about stock can be asked where the work is
already happening instead of in a separate tab.

It is deliberately thin. Every tool here reads through ``facts.fact_store``, the
same layer behind ``/api/chat`` and the app's Reports screen, so all three quote
the same number. A second implementation of "what is low on stock" that drifted
from the first would be worse than no MCP server at all.

**Security model, stated plainly.** stdio has no per-request identity: the
client is a local process the user launched, and there is no bearer token to
verify per call. So the workspace is fixed for the life of the process by
``MCP_COMPANY_ID``, and Firestore access uses whatever service-account
credentials that process was given. That is a real narrowing compared with the
HTTP API, where every call re-proves membership — and it is why writes are off
unless ``MCP_ALLOW_WRITES=1`` is set, and why even then they run through the
same ``may_run_tool`` choke point as the agent, against the grants in
``MCP_PERMISSIONS``.

Run it:

    MCP_COMPANY_ID=<workspace> venv/bin/python mcp_server.py

Claude Desktop config (``claude_desktop_config.json``):

    {
      "mcpServers": {
        "inventory": {
          "command": "/abs/path/rag_backend/venv/bin/python",
          "args": ["/abs/path/rag_backend/mcp_server.py"],
          "env": {
            "MCP_COMPANY_ID": "your-workspace-id",
            "GOOGLE_APPLICATION_CREDENTIALS": "/abs/path/service-account.json"
          }
        }
      }
    }
"""

from __future__ import annotations

import os
import sys
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.server.mcpserver import MCPServer

import nodes
from facts import InventoryFacts, fact_store
from resolver import ProductResolver

COMPANY_ID = os.environ.get("MCP_COMPANY_ID", "").strip()
ALLOW_WRITES = os.environ.get("MCP_ALLOW_WRITES", "").strip() in {"1", "true", "yes"}
# Grants this process holds, comma-separated, or "*" for admin. Only consulted
# when writes are enabled at all.
PERMISSIONS = {
    p.strip()
    for p in os.environ.get("MCP_PERMISSIONS", "").split(",")
    if p.strip()
}

server = MCPServer(
    name="smartshelfkart-inventory",
    version="1.0.0",
    instructions=(
        "Live inventory for a SmartShelfKart workspace: stock levels, reorder "
        "planning, valuation and dead stock. Figures come from the same fact "
        "layer as the app's Reports screen, so they will agree with it.\n\n"
        "Every product named in a result exists in the catalog. If a product "
        "cannot be found, say so — do not offer a plausible substitute, and do "
        "not invent a SKU."
    ),
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _require_company() -> str:
    if not COMPANY_ID:
        raise ValueError(
            "MCP_COMPANY_ID is not set. This server refuses to guess a "
            "workspace: there is no default tenant, because defaulting to one "
            "is how one workspace ends up reading another's stock."
        )
    return COMPANY_ID


def _facts() -> InventoryFacts:
    return fact_store.get(_require_company(), force=False)


def _rows(products: List[Any], limit: int = 50) -> List[Dict[str, Any]]:
    return [p.brief() for p in products[:limit]]


def _resolve(facts: InventoryFacts, query: str):
    """Exact match first, then the fuzzy resolver the agent uses."""
    direct = facts.lookup(query)
    if direct is not None:
        return direct, 1.0
    resolution = ProductResolver(facts.products).resolve(query)
    return resolution.product, resolution.confidence


# ---------------------------------------------------------------------------
# Read tools
# ---------------------------------------------------------------------------


@server.tool(
    description=(
        "Headline inventory figures for the workspace: product count, how many "
        "are low or out of stock, total retail and cost value, and whether "
        "sales history is complete enough to trust demand-based numbers."
    )
)
def inventory_summary() -> Dict[str, Any]:
    facts = _facts()
    summary = dict(facts.summary())
    # Said out loud rather than left for the caller to infer from a zero: with
    # no transactions recorded, burn rate and days-of-cover are undefined, not
    # zero, and an assistant that reports "0 per day" invents a fact.
    summary["demand_figures_reliable"] = facts.history_is_reliable
    if not facts.history_is_reliable:
        summary["note"] = (
            "No stock movements recorded in the window, so burn rate, days of "
            "cover and dead-stock analysis cannot be computed. This reflects "
            "missing transaction records, not products that are not selling."
        )
    return summary


@server.tool(
    description=(
        "Products at or below their low-stock threshold, plus anything already "
        "at zero. The list the buyer works from."
    )
)
def low_stock(limit: int = 50) -> Dict[str, Any]:
    facts = _facts()
    out_of_stock = facts.out_of_stock
    low = facts.low_stock
    return {
        "out_of_stock_count": len(out_of_stock),
        "low_stock_count": len(low),
        "products": _rows(out_of_stock + low, limit),
    }


@server.tool(
    description=(
        "What to reorder and how much, from demand over the last 90 days and "
        "supplier lead time. Returns an empty plan when nothing is due."
    )
)
def reorder_plan(limit: int = 50) -> Dict[str, Any]:
    facts = _facts()
    due = facts.needs_reorder
    return {
        "count": len(due),
        "demand_figures_reliable": facts.history_is_reliable,
        "products": _rows(due, limit),
    }


@server.tool(
    description=(
        "Inventory valuation: retail value, cost basis and the unrealised "
        "margin between them."
    )
)
def valuation() -> Dict[str, Any]:
    facts = _facts()
    summary = facts.summary()
    return {
        "retail_value": summary.get("total_inventory_value", 0.0),
        "cost_value": summary.get("total_cost_value", 0.0),
        "unrealised_margin": summary.get("unrealized_margin", 0.0),
        "products": summary.get("total_products", 0),
    }


@server.tool(
    description=(
        "Find a product by name, barcode or a partial/misspelled name. Returns "
        "the match with a confidence score, and the alternatives it was chosen "
        "over so an ambiguous query can be disambiguated rather than guessed."
    )
)
def find_product(query: str) -> Dict[str, Any]:
    facts = _facts()
    product, confidence = _resolve(facts, query)
    if product is None:
        candidates = ProductResolver(facts.products).search(query, limit=5)
        return {
            "found": False,
            "query": query,
            "message": f"No product in this catalog matches {query!r}.",
            "did_you_mean": [c.name for c in candidates],
            # So a miss is distinguishable from an empty workspace, and so the
            # caller has something true to offer instead of guessing a name.
            "catalog_size": len(facts.products),
        }
    return {
        "found": True,
        "confidence": round(confidence, 2),
        "product": product.to_dict(),
    }


@server.tool(
    description=(
        "Stock that has not moved: how long it has sat still and the capital it "
        "ties up. Requires recorded sales history; says so when there is none."
    )
)
def dead_stock(limit: int = 50) -> Dict[str, Any]:
    facts = _facts()
    if not facts.history_is_reliable:
        return {
            "available": False,
            "reason": (
                "No stock movements recorded in the last 90 days, so nothing "
                "can be called dead. This is missing history, not stagnant stock."
            ),
        }
    rows = facts.dead_stock
    return {"available": True, "count": len(rows), "products": _rows(rows, limit)}


@server.tool(
    description=(
        "The full catalog, briefly. Prefer the narrower tools; this is for when "
        "a question genuinely needs every row."
    )
)
def list_products(limit: int = 200) -> Dict[str, Any]:
    facts = _facts()
    return {"count": len(facts.products), "products": _rows(facts.products, limit)}


# ---------------------------------------------------------------------------
# Write tool
# ---------------------------------------------------------------------------


@server.tool(
    description=(
        "Adjust a product's stock level. Disabled unless the server was started "
        "with MCP_ALLOW_WRITES=1, and then still subject to the same permission "
        "grants the app enforces."
    )
)
def adjust_stock(product: str, qty_change: int, reason: str = "MCP adjustment") -> Dict[str, Any]:
    if not ALLOW_WRITES:
        return {
            "success": False,
            "error": "writes_disabled",
            "message": (
                "This inventory server is read-only. Start it with "
                "MCP_ALLOW_WRITES=1 to permit stock changes."
            ),
        }

    # The same choke point the agent's writes pass through, so a grant withheld
    # in the app is withheld here. `writes.py` goes through the Admin SDK, which
    # bypasses firestore.rules entirely — without this the MCP server would be a
    # way around every permission in the product.
    if not nodes.may_run_tool("update_stock", PERMISSIONS or None):
        return {
            "success": False,
            "error": "permission_denied",
            "message": (
                "This server does not hold canAdjustStock. Set MCP_PERMISSIONS "
                "if the account behind it is meant to have it."
            ),
        }

    company_id = _require_company()
    facts = _facts()
    match, confidence = _resolve(facts, product)
    if match is None:
        return {
            "success": False,
            "error": "product_not_found",
            "message": f"No product in this catalog matches {product!r}. Nothing was changed.",
        }
    if confidence < 0.75:
        # Refusing a low-confidence match is the point: silently adjusting the
        # wrong product is worse than adjusting nothing.
        return {
            "success": False,
            "error": "ambiguous_product",
            "message": (
                f"{product!r} is closest to {match.name!r}, but not closely "
                f"enough to move stock on it. Name the product exactly."
            ),
        }

    import writes

    # `writes.update_stock` takes the resolved ProductFact, not a name: the
    # resolution has already happened above and re-doing it inside the write
    # would be a second chance to pick a different product.
    result = writes.update_stock(
        product=match,
        qty_change=int(qty_change),
        reason=reason,
        company_id=company_id,
    )
    fact_store.bump(company_id)
    return result


# ---------------------------------------------------------------------------
# Resource
# ---------------------------------------------------------------------------


@server.resource(
    "inventory://summary",
    description="Headline inventory figures, refreshed on read.",
    mime_type="application/json",
)
def summary_resource() -> Dict[str, Any]:
    return inventory_summary()


def main() -> None:
    if not COMPANY_ID:
        print(
            "MCP_COMPANY_ID is not set — every tool will refuse until it is.",
            file=sys.stderr,
        )
    mode = "read/write" if ALLOW_WRITES else "read-only"
    print(f"[mcp] inventory server starting ({mode})", file=sys.stderr)
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
