"""
FastAPI surface for the inventory agent.

Two things changed structurally here:

* `/api/chat/stream` used to run the graph to completion and then re-emit the
  finished string in three-word chunks. It looked like streaming and delivered
  none of the benefit — time-to-first-token was the full generation time. It now
  forwards real model tokens as they arrive.
* Everything used to be pushed onto the default executor with
  `run_in_executor(None, ...)`, which throttles Cloud Run concurrency. The graph
  is async end to end now.

Answers are cached against a fingerprint of the live inventory, so a stock
change anywhere rotates the key and stale answers become unreachable.
"""

import asyncio
import voice
import json
import re
from typing import Any, Dict, List, Optional, Set

import uvicorn
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

load_dotenv()

import auth
import deterministic
import llm as llm_factory
import writes
from cache import answer_cache
from facts import fact_store
from graph import rag_pipeline
from inventory_db import db_instance
from resolver import ProductResolver

app = FastAPI(
    title="Inventory Agent API",
    description="Grounded, tool-calling inventory assistant over live Firestore data",
)

# The app's own origins only. This was "*", which combined with the missing
# token check meant any page on the internet could read a tenant's inventory.
_ALLOWED_ORIGINS = [
    "https://stockmanagement-27af8.web.app",
    "https://stockmanagement-27af8.firebaseapp.com",
    "https://smartshelfkart.com",
    "https://www.smartshelfkart.com",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "x-company-id"],
)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class ChatMessage(BaseModel):
    role: str
    content: str


class QueryRequest(BaseModel):
    question: str
    context: Optional[str] = None
    history: Optional[List[ChatMessage]] = None
    company_id: Optional[str] = "default"
    business_type: Optional[str] = "retail_store"
    session_id: Optional[str] = None


class QueryResponse(BaseModel):
    answer: str
    retries: int = 0
    intent: Optional[str] = "KNOWLEDGE"
    executed_actions: Optional[List[Dict[str, Any]]] = []
    analytics_data: Optional[Dict[str, Any]] = None
    updated_catalog: Optional[List[Dict[str, Any]]] = None
    answered_by: Optional[str] = None
    clarification_options: Optional[List[Dict[str, Any]]] = None
    pending_action: Optional[Dict[str, Any]] = None
    response_kind: Optional[str] = "prose"


def _cid(header: Optional[str], body: Optional[str]) -> str:
    """Unverified company id. Only /health may use this — every other route
    goes through auth.verified_company_id, which proves the caller is a member."""
    cid = (header or body or "").strip()
    if not cid or cid == "default":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "company_id_required",
                "message": "No workspace was identified for this request."
            }
        )
    return cid


def _sid(request: QueryRequest, company_id: str) -> str:
    return (request.session_id or company_id or "default").strip() or "default"


def _inputs(
    request: QueryRequest,
    company_id: str,
    permissions: Optional[Set[str]] = None,
) -> Dict[str, Any]:
    return {
        "question": request.question,
        "retries": 0,
        "provided_context": request.context,
        "history": [h.model_dump() for h in request.history] if request.history else [],
        "company_id": company_id,
        "business_type": request.business_type or "retail_store",
        "session_id": _sid(request, company_id),
        # Carried into the graph so the write choke point can refuse a change
        # the caller is not entitled to make. Reads are unaffected.
        "permissions": permissions,
    }


def _catalog_if_mutated(state: Dict[str, Any], company_id: str) -> Optional[List[Dict[str, Any]]]:
    if not state.get("executed_actions"):
        return None
    facts = fact_store.get(company_id, force=True)
    return [
        {
            "id": p.id,
            "barcode": p.barcode,
            "name": p.name,
            "stock": p.quantity,
            "quantity": p.quantity,
            "min_threshold": p.min_threshold,
            "category": p.category,
            "cost_price": p.cost_price,
            "selling_price": p.selling_price,
        }
        for p in facts.products
    ]


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------

@app.post("/api/chat", response_model=QueryResponse)
async def chat_endpoint(
    request: QueryRequest,
    principal: auth.Principal = Depends(auth.verified_principal_rate_limited),
):
    company_id = principal.company_id
    business_type = request.business_type or "retail_store"

    facts = await asyncio.to_thread(fact_store.get, company_id)
    cached = answer_cache.get(
        request.question, company_id, facts.fingerprint, business_type
    )
    if cached:
        return QueryResponse(
            answer=cached["answer"],
            intent=cached.get("intent", "KNOWLEDGE"),
            analytics_data=cached.get("analytics_data"),
            executed_actions=[],
            answered_by="cache",
            clarification_options=cached.get("clarification_options"),
            response_kind=cached.get("response_kind", "prose"),
        )

    inputs = _inputs(request, company_id, principal.granted())
    inputs["facts"] = facts
    state = await rag_pipeline.ainvoke(inputs)

    answer = state.get("generation") or "I couldn't produce an answer for that."
    intent = state.get("intent", "KNOWLEDGE")
    executed = state.get("executed_actions") or []

    if executed:
        answer_cache.clear(company_id)
    else:
        answer_cache.set(
            request.question,
            company_id,
            facts.fingerprint,
            {
                "answer": answer,
                "intent": intent,
                "analytics_data": state.get("analytics_data"),
                "clarification_options": state.get("clarification_options"),
                "response_kind": state.get("response_kind", "prose"),
            },
            business_type,
        )

    return QueryResponse(
        answer=answer,
        retries=state.get("retries", 0),
        intent=intent,
        executed_actions=executed,
        analytics_data=state.get("analytics_data"),
        updated_catalog=_catalog_if_mutated(state, company_id),
        answered_by=state.get("answered_by"),
        clarification_options=state.get("clarification_options"),
        pending_action=state.get("pending_action"),
        response_kind=state.get("response_kind", "prose"),
    )


# `[STATS: {...}]` and friends are machine-readable trailers, not prose. They
# belong in the final `answer` (where the client parses them into metric cards),
# never in the visible token stream.
_TAGGED_BLOCK = re.compile(r"\[(?:STATS|ACTION|PENDING):.*?\]", re.DOTALL)


def _display_text(text: str) -> str:
    return _TAGGED_BLOCK.sub("", text or "").strip()


def _sse(payload: Dict[str, Any]) -> str:
    return f"data: {json.dumps(payload)}\n\n"


@app.post("/api/chat/stream")
async def stream_chat_endpoint(
    request: QueryRequest,
    principal: auth.Principal = Depends(auth.verified_principal_rate_limited),
):
    company_id = principal.company_id
    business_type = request.business_type or "retail_store"

    async def events():
        facts = await asyncio.to_thread(fact_store.get, company_id)

        cached = answer_cache.get(
            request.question, company_id, facts.fingerprint, business_type
        )
        if cached:
            yield _sse({"type": "status", "message": "Answering from cache"})
            yield _sse({"type": "delta", "content": _display_text(cached["answer"])})
            yield _sse(
                {
                    "type": "done",
                    "answer": cached["answer"],
                    "intent": cached.get("intent", "KNOWLEDGE"),
                    "analytics_data": cached.get("analytics_data"),
                    "executed_actions": [],
                    "clarification_options": cached.get("clarification_options"),
                    "response_kind": cached.get("response_kind", "prose"),
                }
            )
            return

        yield _sse({"type": "status", "message": "Reading live inventory..."})

        inputs = _inputs(request, company_id, principal.granted())
        inputs["facts"] = facts

        state: Dict[str, Any] = {}
        streamed = False
        announced_intent = False

        try:
            async for event in rag_pipeline.astream_events(inputs, version="v2"):
                kind = event.get("event")

                if kind == "on_chain_end" and event.get("name") == "router":
                    data = (event.get("data") or {}).get("output") or {}
                    intent = data.get("intent") if isinstance(data, dict) else None
                    if intent and not announced_intent:
                        announced_intent = True
                        yield _sse(
                            {
                                "type": "status",
                                "message": {
                                    "EXECUTION": "Checking the product and stock levels...",
                                    "ANALYTICS": "Crunching your inventory numbers...",
                                }.get(intent, "Thinking..."),
                            }
                        )

                elif kind == "on_chat_model_stream":
                    chunk = (event.get("data") or {}).get("chunk")
                    text = getattr(chunk, "content", "") or ""
                    if isinstance(text, list):
                        text = "".join(
                            p.get("text", "") if isinstance(p, dict) else str(p)
                            for p in text
                        )
                    if text:
                        streamed = True
                        yield _sse({"type": "delta", "content": text})

                elif kind == "on_chain_end" and event.get("name") == "LangGraph":
                    output = (event.get("data") or {}).get("output")
                    if isinstance(output, dict):
                        state = output
        except Exception as exc:
            print(f"[stream] pipeline failed: {exc}")
            yield _sse(
                {
                    "type": "done",
                    "answer": "Something went wrong reaching the assistant. Please try again.",
                    "intent": "KNOWLEDGE",
                }
            )
            return

        answer = state.get("generation") or "I couldn't produce an answer for that."
        intent = state.get("intent", "KNOWLEDGE")
        executed = state.get("executed_actions") or []

        # Deterministic answers and confirmation previews never pass through the
        # model, so nothing streamed — emit them now.
        if not streamed:
            visible = _display_text(answer)
            for i in range(0, len(visible), 120):
                yield _sse({"type": "delta", "content": visible[i : i + 120]})
                await asyncio.sleep(0)

        if executed:
            answer_cache.clear(company_id)
        else:
            answer_cache.set(
                request.question,
                company_id,
                facts.fingerprint,
                {
                    "answer": answer,
                    "intent": intent,
                    "analytics_data": state.get("analytics_data"),
                    "clarification_options": state.get("clarification_options"),
                    "response_kind": state.get("response_kind", "prose"),
                },
                business_type,
            )

        yield _sse(
            {
                "type": "done",
                "answer": answer,
                "intent": intent,
                "executed_actions": executed,
                "analytics_data": state.get("analytics_data"),
                "updated_catalog": _catalog_if_mutated(state, company_id),
                "answered_by": state.get("answered_by"),
                "clarification_options": state.get("clarification_options"),
                "pending_action": state.get("pending_action"),
                "response_kind": state.get("response_kind", "prose"),
            }
        )

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# Inventory sync / ingest
# ---------------------------------------------------------------------------

class ProductIngestItem(BaseModel):
    name: str
    barcode: str
    stock: int
    min_threshold: int = 10
    category: Optional[str] = "General"
    cost_price: Optional[float] = 0.0
    selling_price: Optional[float] = 0.0
    sales_velocity: Optional[float] = 0.0
    lead_time_days: Optional[int] = 3


class ProductIngestRequest(BaseModel):
    products: List[ProductIngestItem]


@app.post("/api/ingest")
async def ingest_endpoint(
    request: ProductIngestRequest,
    # Creates and overwrites product documents, so it needs the same grant the
    # app requires to add a product. Membership alone used to be enough.
    company_id: str = Depends(auth.require_permission("canAddProducts")),
):
    products = [p.model_dump() for p in request.products]
    for product in products:
        db_instance.upsert_product(product, company_id=company_id)
    fact_store.bump(company_id)
    answer_cache.clear(company_id)
    return {
        "status": "success",
        "message": f"Ingested {len(products)} products.",
    }


class InventorySyncRequest(BaseModel):
    products: List[Dict[str, Any]]


@app.post("/api/inventory/sync")
async def sync_inventory_endpoint(
    request: InventorySyncRequest,
    # Replaces the workspace's whole product set — strictly more destructive
    # than editing one, so it is gated on the edit grant.
    company_id: str = Depends(auth.require_permission("canEditProducts")),
):
    if request.products:
        db_instance.replace_user_inventory(request.products, company_id=company_id)
    fact_store.bump(company_id)
    answer_cache.clear(company_id)
    facts = await asyncio.to_thread(fact_store.get, company_id, True)
    return {"status": "success", "synced_items_count": len(facts.products)}


@app.get("/api/inventory")
async def get_inventory(company_id: str = Depends(auth.verified_company_id)):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    return {"products": [p.to_dict() for p in facts.products]}


@app.get("/api/inventory/reconcile")
async def reconcile_inventory(
    company_id: str = Depends(auth.verified_company_id)
):
    """Report products whose total and per-location stock disagree.

    Read-only on purpose. Whether the total or the shelf counts are correct is a
    judgement only the owner can make, so this surfaces the drift and leaves the
    repair to them.
    """
    facts = await asyncio.to_thread(fact_store.get, company_id)
    drift = facts.inconsistencies()
    return {
        "status": "success",
        "products_checked": len(facts.products),
        "inconsistent_count": len(drift),
        "inconsistent": drift[:100],
        "note": (
            "quantity and locationQuantities disagree for these products. "
            "The assistant will refuse to change them until the numbers agree, "
            "so a correction is not applied on top of a wrong figure."
        ),
    }


@app.get("/api/inventory/ledger")
def get_inventory_ledger(company_id: str = Depends(auth.verified_company_id)):
    return {"action_ledger": db_instance._get_company(company_id)["action_ledger"]}


# ---------------------------------------------------------------------------
# Agent endpoints — all now computed from real transaction history
# ---------------------------------------------------------------------------

@app.get("/api/agent/autopilot")
async def autopilot_scan(company_id: str = Depends(auth.verified_company_id)):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    recommendations = [
        {
            "barcode": p.barcode,
            "product_name": p.name,
            "current_stock": p.quantity,
            "available_stock": p.available_qty,
            "min_threshold": p.min_threshold,
            "daily_sales_rate": round(p.daily_burn_rate, 3),
            "weekly_sales_velocity": round(p.daily_burn_rate * 7, 2),
            "lead_time_days": p.lead_time_days,
            "reorder_point": p.reorder_point,
            "safety_stock": p.safety_stock,
            "suggested_reorder_qty": p.suggested_reorder_qty,
            "days_of_cover": None if p.days_of_supply >= 999 else round(p.days_of_supply, 1),
            "urgency": (
                "HIGH"
                if p.quantity <= 0 or p.days_of_supply <= p.lead_time_days
                else "MEDIUM"
            ),
        }
        for p in facts.needs_reorder
    ]
    return {
        "status": "success",
        "timestamp": facts.summary(),
        "recommendations_count": len(recommendations),
        "recommendations": recommendations,
    }


@app.get("/api/agent/forecast")
async def predictive_forecast(company_id: str = Depends(auth.verified_company_id)):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    forecasts = [
        {
            "barcode": p.barcode,
            "product_name": p.name,
            "current_stock": p.quantity,
            "available_stock": p.available_qty,
            "daily_sales_rate": round(p.daily_burn_rate, 3),
            "demand_std_dev": round(p.demand_std_dev, 3),
            "statistical_safety_stock": p.safety_stock,
            "projected_30d_demand": round(p.daily_burn_rate * 30, 1),
            "days_until_stockout": round(p.days_of_supply, 1),
            "risk_level": {
                "at_risk": "CRITICAL",
                "dead_stock": "NONE",
                "no_history": "UNKNOWN",
                "overstocked": "LOW",
                "optimal": "MEDIUM",
            }.get(p.health, "UNKNOWN"),
            "revenue_at_risk": round(p.daily_burn_rate * p.lead_time_days * p.selling_price, 2),
            "recommendation": (
                f"Order {p.suggested_reorder_qty} units now"
                if p.needs_reorder
                else "No movement recorded - demand unknown"
                if p.health == "no_history"
                else "No action needed"
            ),
            "units_sold_in_window": p.units_out_window,
            "window_days": facts.window_days,
        }
        for p in sorted(facts.products, key=lambda x: x.days_of_supply)
    ]
    return {
        "status": "success",
        "forecasts_count": len(forecasts),
        "has_sales_history": facts.summary()["has_sales_history"],
        "forecasts": forecasts,
    }


@app.get("/api/agent/anomalies")
async def detect_anomalies(company_id: str = Depends(auth.verified_company_id)):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    anomalies: List[Dict[str, Any]] = []

    for p in facts.products:
        if p.quantity <= 0 and p.daily_burn_rate > 0:
            anomalies.append(
                {
                    "type": "STOCKOUT_ON_MOVING_ITEM",
                    "product_name": p.name,
                    "barcode": p.barcode,
                    "severity": "CRITICAL",
                    "description": (
                        f"Out of stock while selling {p.daily_burn_rate:.2f} units/day — "
                        f"roughly {p.daily_burn_rate * p.selling_price:,.2f} of revenue lost per day."
                    ),
                }
            )
        elif p.needs_reorder and p.days_of_supply <= p.lead_time_days:
            anomalies.append(
                {
                    "type": "INSIDE_LEAD_TIME",
                    "product_name": p.name,
                    "barcode": p.barcode,
                    "severity": "HIGH",
                    "description": (
                        f"{p.days_of_supply:.0f} days of cover left but the supplier needs "
                        f"{p.lead_time_days} days — a stockout is already committed unless you order today."
                    ),
                }
            )
        elif p.health == "dead_stock" and p.cost_value > 0 and facts.history_is_reliable:
            anomalies.append(
                {
                    "type": "DEAD_STOCK",
                    "product_name": p.name,
                    "barcode": p.barcode,
                    "severity": "MEDIUM",
                    "description": (
                        f"No movement in {facts.window_days} days with "
                        f"{p.cost_value:,.2f} of capital tied up."
                    ),
                }
            )

    order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
    anomalies.sort(key=lambda a: order.get(a["severity"], 9))
    return {
        "status": "success",
        "anomalies_count": len(anomalies),
        "anomalies": anomalies,
    }


@app.get("/api/agent/safety_stock")
async def statistical_safety_stock_endpoint(
    company_id: str = Depends(auth.verified_company_id)
):
    facts = await asyncio.to_thread(fact_store.get, company_id)

    # ABC by annualised revenue contribution from real movement.
    ranked = sorted(
        facts.products,
        key=lambda p: -(p.units_out_window * p.selling_price),
    )
    total_value = sum(p.units_out_window * p.selling_price for p in ranked) or 1.0
    abc: Dict[str, List[str]] = {"A": [], "B": [], "C": []}
    cumulative = 0.0
    for p in ranked:
        cumulative += p.units_out_window * p.selling_price
        share = cumulative / total_value
        abc["A" if share <= 0.8 else "B" if share <= 0.95 else "C"].append(p.barcode)

    grade = {bc: g for g, items in abc.items() for bc in items}
    return {
        "status": "success",
        "safety_stock_recommendations_count": len(facts.products),
        "abc_analysis_summary": {k: len(v) for k, v in abc.items()},
        "recommendations": [
            {
                "barcode": p.barcode,
                "name": p.name,
                "current_stock": p.quantity,
                "daily_sales_rate": round(p.daily_burn_rate, 3),
                "demand_std_dev": round(p.demand_std_dev, 3),
                "lead_time_days": p.lead_time_days,
                "statistical_safety_stock": p.safety_stock,
                "reorder_point_rop": p.reorder_point,
                "abc_class": grade.get(p.barcode, "C"),
                "status": "REORDER_NEEDED" if p.needs_reorder else "OPTIMAL",
            }
            for p in facts.products
        ],
    }


@app.get("/api/agent/location_balance")
async def location_balance(company_id: str = Depends(auth.verified_company_id)):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    suggestions = []
    for p in facts.products:
        locations = {k: v for k, v in p.location_quantities.items() if v}
        if len(locations) < 2:
            continue
        richest = max(locations, key=lambda k: locations[k])
        poorest = min(locations, key=lambda k: locations[k])
        surplus = locations[richest]
        deficit = locations[poorest]
        if surplus > max(p.min_threshold, 1) * 2 and deficit <= p.min_threshold:
            suggestions.append(
                {
                    "barcode": p.barcode,
                    "product_name": p.name,
                    "from_location": richest,
                    "to_location": poorest,
                    "suggested_transfer_qty": max(1, (surplus - deficit) // 2),
                    "reason": (
                        f"{richest} holds {surplus} units while {poorest} is down to "
                        f"{deficit}, below its {p.min_threshold} threshold."
                    ),
                }
            )
    return {
        "status": "success",
        "transfer_suggestions_count": len(suggestions),
        "transfer_suggestions": suggestions,
    }


# ---------------------------------------------------------------------------
# Visual audit & voice
# ---------------------------------------------------------------------------

class VisualAuditItem(BaseModel):
    name: str
    count: int


class VisualAuditRequest(BaseModel):
    detected_items: List[VisualAuditItem]


@app.post("/api/agent/visual_audit")
async def process_visual_audit(
    request: VisualAuditRequest,
    # Writes counted quantities straight over system stock — the same thing a
    # stock adjustment does, so it takes the same grant.
    company_id: str = Depends(auth.require_permission("canAdjustStock")),
):
    auth.rate_limit(company_id)
    facts = await asyncio.to_thread(fact_store.get, company_id, True)
    resolver = ProductResolver(facts.products)

    results = []
    for item in request.detected_items:
        resolution = resolver.resolve(item.name)
        if resolution.status == "not_found":
            results.append({"product_name": item.name, "error": "Product not found in catalog"})
            continue
        if resolution.status == "ambiguous":
            results.append(
                {
                    "product_name": item.name,
                    "error": "Ambiguous match — confirm which product",
                    "candidates": resolution.options(),
                }
            )
            continue

        product = resolution.product
        outcome = await asyncio.to_thread(
            writes.audit_inventory,
            product,
            item.count,
            f"Visual audit: counted {item.count}",
            company_id,
        )
        results.append(
            {
                "product_name": product.name,
                "barcode": product.barcode,
                "expected_stock": product.quantity,
                "visual_counted_stock": item.count,
                "discrepancy": item.count - product.quantity,
                "success": outcome.get("success", False),
            }
        )

    answer_cache.clear(company_id)
    return {
        "status": "success",
        "audit_summary": {
            "timestamp": facts.generated_at,
            "audited_items_count": len(results),
            "results": results,
        },
    }


class VoiceCommandRequest(BaseModel):
    speech_text: str


@app.post("/api/agent/voice_command")
async def process_voice_command_endpoint(
    request: VoiceCommandRequest,
    # Spoken commands move stock, so this is a write route despite reading like
    # a query one.
    company_id: str = Depends(auth.require_permission("canAdjustStock")),
):
    auth.rate_limit(company_id)
    result = await asyncio.to_thread(
        voice.process_voice_command, request.speech_text, company_id
    )
    fact_store.bump(company_id)
    answer_cache.clear(company_id)
    return result


# ---------------------------------------------------------------------------
# Swarm (background autopilot)
# ---------------------------------------------------------------------------

from agent_swarm import AutonomousSwarm

swarm_instance = AutonomousSwarm(db=db_instance)


class SwarmEventRequest(BaseModel):
    event_name: str
    payload: Dict[str, Any] = {}


class SwarmQueryRequest(BaseModel):
    query: str


class POApprovalRequest(BaseModel):
    po_id: str


class GuardrailValidationRequest(BaseModel):
    action_type: str
    payload: Dict[str, Any]
    barcode: Optional[str] = None


@app.post("/api/swarm/trigger")
def trigger_swarm_event(
    request: SwarmEventRequest, company_id: str = Depends(auth.verified_company_id_rate_limited)
):
    return {
        "status": "success",
        "result": swarm_instance.process_event_trigger(
            request.event_name, request.payload, company_id=company_id
        ),
    }


@app.post("/api/swarm/autopilot")
def run_swarm_autopilot(company_id: str = Depends(auth.verified_company_id_rate_limited)):
    return {
        "status": "success",
        "sweep_results": swarm_instance.run_full_autopilot_sweep(company_id=company_id),
        "pending_pos": swarm_instance.pending_pos,
    }


@app.get("/api/swarm/logs")
def get_swarm_logs(company_id: str = Depends(auth.verified_company_id)):
    # Was completely unscoped: it returned the swarm's episodic memory and every
    # pending PO to any caller, across all tenants.
    return {
        "status": "success",
        "episodic_memory": list(swarm_instance.episodic_memory),
        "pending_pos": swarm_instance.pending_pos,
    }


@app.post("/api/swarm/approve_po")
def approve_pending_po_endpoint(
    request: POApprovalRequest,
    # Approving commits a purchase order, so it needs the grant the app requires
    # to raise one. It was previously open to any member of the workspace.
    company_id: str = Depends(auth.require_permission("canCreatePurchaseOrders")),
):
    # Was unauthenticated: anyone could approve any tenant's purchase order by id.
    return swarm_instance.approve_pending_po(request.po_id)


@app.post("/api/swarm/query")
def query_swarm(
    request: SwarmQueryRequest, company_id: str = Depends(auth.verified_company_id_rate_limited)
):
    return {"status": "success", "result": swarm_instance.process_query(request.query, company_id=company_id)}


@app.post("/api/guardrails/validate")
async def validate_guardrails(
    request: GuardrailValidationRequest,
    company_id: str = Depends(auth.verified_company_id),
):
    facts = await asyncio.to_thread(fact_store.get, company_id)
    product = facts.lookup(request.barcode) if request.barcode else None
    item = (
        {"stock": product.quantity, "cost_price": product.cost_price} if product else None
    )
    result = swarm_instance.guardrails.validate_action(
        request.action_type, request.payload, item
    )
    return {
        "status": "success",
        "passed": result.passed,
        "requires_human_approval": result.requires_human_approval,
        "risk_level": result.risk_level,
        "reasons": result.reasons,
        "sanitized_payload": result.sanitized_payload,
    }


# ---------------------------------------------------------------------------
# Ops
# ---------------------------------------------------------------------------

@app.post("/api/cache/clear")
def clear_cache(company_id: str = Depends(auth.verified_company_id)):
    # Scoped to the verified company. Previously a request with no header
    # cleared *every* company's cached answers.
    answer_cache.clear(company_id)
    fact_store.bump(company_id)
    return {"status": "success", "scope": company_id}


@app.get("/api/cache/stats")
def get_cache_stats(company_id: str = Depends(auth.verified_company_id)):
    return {
        "status": "success",
        "answer_cache": answer_cache.stats(),
        "fact_store": fact_store.stats(),
        "llm": llm_factory.health(),
    }


@app.get("/health")
async def health_check():
    # Deliberately unauthenticated so Cloud Run can probe it, and deliberately
    # tenant-free: it used to accept an x-company-id and report that workspace's
    # inventory fingerprint and source, which leaked whether a company id was
    # real to anyone who asked.
    payload: Dict[str, Any] = {
        "status": "ok",
        "llm": llm_factory.health()["models"],
        "provider": llm_factory.active_provider() or "lazy",
    }
    return payload


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
