import json
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import uvicorn
from dotenv import load_dotenv
load_dotenv()

from fastapi.middleware.cors import CORSMiddleware
from graph import rag_pipeline
from cache_manager import CacheManager
from semantic_cache import SemanticCacheManager
from inventory_db import db_instance

app = FastAPI(
    title="Action-Oriented AI Stock Management API",
    description="Autonomous Agentic AI Engine for Real-Time Inventory Control and Decisioning"
)
cache_manager = CacheManager()
semantic_cache = SemanticCacheManager()


# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatMessage(BaseModel):
    role: str
    content: str

class QueryRequest(BaseModel):
    question: str
    context: Optional[str] = None
    history: Optional[List[ChatMessage]] = None
    company_id: Optional[str] = "default"

class QueryResponse(BaseModel):
    answer: str
    retries: int = 0
    intent: Optional[str] = "KNOWLEDGE"
    executed_actions: Optional[List[Dict[str, Any]]] = []
    analytics_data: Optional[Dict[str, Any]] = None
    updated_catalog: Optional[List[Dict[str, Any]]] = None

from fastapi.responses import StreamingResponse
import asyncio

@app.post("/api/chat", response_model=QueryResponse)
async def chat_endpoint(request: QueryRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    cid = x_company_id or request.company_id or "default"
    history_list = [h.model_dump() for h in request.history] if request.history else []
    
    # 1. Check persistent & vector semantic cache for instant response (< 50ms)
    cached_val = cache_manager.get(request.question, request.context, history_list)
    if not cached_val:
        semantic_res = semantic_cache.get(request.question)
        if semantic_res and isinstance(semantic_res, dict):
            cached_val = semantic_res.get("generation")

    if cached_val:
        return QueryResponse(
            answer=cached_val,
            retries=0,
            intent="KNOWLEDGE",
            executed_actions=[],
            analytics_data=None,
            updated_catalog=None
        )

    inputs = {
        "question": request.question, 
        "retries": 0,
        "provided_context": request.context,
        "history": history_list,
        "company_id": cid
    }

    # 2. Invoke multi-agent pipeline
    final_state = rag_pipeline.invoke(inputs)
    generation = final_state.get("generation", "No response generated.")
    intent = final_state.get("intent", "KNOWLEDGE")
    executed_actions = final_state.get("executed_actions", [])
    analytics_data = final_state.get("analytics_data")
    
    updated_cat = None
    # 3. If actions executed (stock mutated), invalidate stale cache & return updated catalog
    if executed_actions:
        cache_manager.clear()
        semantic_cache.clear()
        updated_cat = db_instance.get_all_products(company_id=cid)
    elif intent in ["KNOWLEDGE", "ANALYTICS"] and generation:
        cache_manager.set(request.question, request.context, history_list, generation)
        semantic_cache.set(request.question, {"generation": generation, "intent": intent})

    return QueryResponse(
        answer=generation,
        retries=final_state.get("retries", 0),
        intent=intent,
        executed_actions=executed_actions,
        analytics_data=analytics_data,
        updated_catalog=updated_cat
    )


@app.post("/api/chat/stream")
async def stream_chat_endpoint(request: QueryRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    cid = x_company_id or request.company_id or "default"
    history_list = [h.model_dump() for h in request.history] if request.history else []
    
    async def event_generator():
        # 1. Check cache for instant streaming (< 5ms)
        cached_val = cache_manager.get(request.question, request.context, history_list)
        if cached_val:
            yield f"data: {json.dumps({'type': 'status', 'message': 'Cache hit - instant response'})}\n\n"
            # Stream words progressively to simulate instant fluid typing
            words = cached_val.split(" ")
            for i in range(0, len(words), 3):
                chunk = " ".join(words[i:i+3]) + " "
                yield f"data: {json.dumps({'type': 'delta', 'content': chunk})}\n\n"
                await asyncio.sleep(0.01)
            yield f"data: {json.dumps({'type': 'done', 'answer': cached_val, 'intent': 'KNOWLEDGE'})}\n\n"
            return

        yield f"data: {json.dumps({'type': 'status', 'message': 'Routing intent & auditing inventory...'})}\n\n"
        
        inputs = {
            "question": request.question, 
            "retries": 0,
            "provided_context": request.context,
            "history": history_list,
            "company_id": cid
        }

        # Run pipeline in background executor to avoid blocking event loop
        loop = asyncio.get_event_loop()
        final_state = await loop.run_in_executor(None, rag_pipeline.invoke, inputs)
        
        generation = final_state.get("generation", "No response generated.")
        intent = final_state.get("intent", "KNOWLEDGE")
        executed_actions = final_state.get("executed_actions", [])
        analytics_data = final_state.get("analytics_data")

        if executed_actions:
            cache_manager.clear()
            updated_cat = db_instance.get_all_products(company_id=cid)
        elif intent in ["KNOWLEDGE", "ANALYTICS"] and generation:
            cache_manager.set(request.question, request.context, history_list, generation)
            updated_cat = None
        else:
            updated_cat = None

        # Stream out response
        words = generation.split(" ")
        for i in range(0, len(words), 3):
            chunk = " ".join(words[i:i+3]) + " "
            yield f"data: {json.dumps({'type': 'delta', 'content': chunk})}\n\n"
            await asyncio.sleep(0.015)

        yield f"data: {json.dumps({'type': 'done', 'answer': generation, 'intent': intent, 'executed_actions': executed_actions, 'analytics_data': analytics_data, 'updated_catalog': updated_cat})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

class ProductIngestItem(BaseModel):
    name: str
    barcode: str
    stock: int
    min_threshold: int = 10
    category: Optional[str] = "General"
    cost_price: Optional[float] = 0.0
    selling_price: Optional[float] = 0.0
    sales_velocity: Optional[int] = 0
    lead_time_days: Optional[int] = 3

class ProductIngestRequest(BaseModel):
    products: List[ProductIngestItem]

@app.post("/api/ingest")
async def ingest_endpoint(request: ProductIngestRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    cid = x_company_id or "default"
    prods = [p.model_dump() for p in request.products]
    for p in prods:
        db_instance.upsert_product(p, company_id=cid)
    
    # Also index into ChromaDB if available
    try:
        from ingest import ingest_custom_products
        ingest_custom_products(prods)
    except Exception as e:
        print(f"Vector ingest warning: {e}")
        
    cache_manager.clear()
    return {"status": "success", "message": f"Ingested {len(prods)} products into live inventory database & vectorstore."}

@app.get("/api/agent/autopilot")
def autopilot_scan(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Proactively scans inventory levels, calculates reorder point requirements based on sales velocity and lead times,
    and returns automated purchase recommendations.
    """
    cid = x_company_id or "default"
    recommendations = db_instance.run_autopilot_scan(company_id=cid)
    metrics = db_instance.get_analytics_summary(company_id=cid)
    return {
        "status": "success",
        "timestamp": metrics,
        "recommendations_count": len(recommendations),
        "recommendations": recommendations
    }

@app.get("/api/agent/anomalies")
def detect_anomalies(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Scans action ledger and current stock state for anomalies, unexpected shrinkages, and stockout threats.
    """
    cid = x_company_id or "default"
    anomalies = db_instance.detect_inventory_anomalies(company_id=cid)
    return {
        "status": "success",
        "anomalies_count": len(anomalies),
        "anomalies": anomalies
    }

@app.get("/api/agent/forecast")
def predictive_forecast(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Returns 30-day predictive time-series demand forecasts, stockout projections, and optimal reorder windows.
    """
    cid = x_company_id or "default"
    forecasts = db_instance.get_predictive_demand_forecast(company_id=cid)
    return {
        "status": "success",
        "forecasts_count": len(forecasts),
        "forecasts": forecasts
    }

@app.get("/api/agent/safety_stock")
def statistical_safety_stock_endpoint(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Returns statistical safety stock levels and optimal reorder points for all inventory SKUs.
    """
    cid = x_company_id or "default"
    try:
        from predictive_ml import calculate_statistical_safety_stock, calculate_reorder_point, perform_abc_analysis
    except ImportError:
        from .predictive_ml import calculate_statistical_safety_stock, calculate_reorder_point, perform_abc_analysis

    all_prods = db_instance.get_all_products(company_id=cid)
    abc_groups = perform_abc_analysis(all_prods)
    
    results = []
    for p in all_prods:
        velocity = p.get("sales_velocity", 1.0)
        lead_days = p.get("lead_time_days", 3)
        safety_stock = calculate_statistical_safety_stock(velocity, lead_days)
        rop = calculate_reorder_point(velocity, lead_days, safety_stock)
        results.append({
            "barcode": p.get("barcode"),
            "name": p.get("name"),
            "current_stock": p.get("stock", 0),
            "sales_velocity": velocity,
            "lead_time_days": lead_days,
            "statistical_safety_stock": safety_stock,
            "reorder_point_rop": rop,
            "status": "REORDER_NEEDED" if p.get("stock", 0) <= rop else "OPTIMAL"
        })
        
    return {
        "status": "success",
        "safety_stock_recommendations_count": len(results),
        "abc_analysis_summary": {k: len(v) for k, v in abc_groups.items()},
        "recommendations": results
    }


@app.get("/api/agent/location_balance")
def location_balance(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Analyzes cross-location stock distribution and returns automated stock transfer recommendations.
    """
    cid = x_company_id or "default"
    transfers = db_instance.get_cross_location_balance_suggestions(company_id=cid)
    return {
        "status": "success",
        "transfer_suggestions_count": len(transfers),
        "transfer_suggestions": transfers
    }

class VisualAuditItem(BaseModel):
    name: str
    count: int

class VisualAuditRequest(BaseModel):
    detected_items: List[VisualAuditItem]

@app.post("/api/agent/visual_audit")
def process_visual_audit(request: VisualAuditRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Processes visual camera audit counts against live stock database and logs adjustments.
    """
    cid = x_company_id or "default"
    items = [i.model_dump() for i in request.detected_items]
    audit_summary = db_instance.process_visual_audit_photo(items, company_id=cid)
    cache_manager.clear()
    semantic_cache.clear()
    return {
        "status": "success",
        "audit_summary": audit_summary
    }

class VoiceCommandRequest(BaseModel):
    speech_text: str

@app.post("/api/agent/voice_command")
def process_voice_command_endpoint(request: VoiceCommandRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Processes hands-free spoken inventory commands and returns atomic stock mutations with text-to-speech audio feedback.
    """
    cid = x_company_id or "default"
    res = db_instance.process_voice_command(request.speech_text, company_id=cid)
    cache_manager.clear()
    semantic_cache.clear()
    return res

@app.get("/api/inventory")
def get_inventory(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """Returns list of all products in the live inventory database."""
    cid = x_company_id or "default"
    return {"products": db_instance.get_all_products(company_id=cid)}


@app.get("/api/inventory/ledger")
def get_inventory_ledger(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """Returns audit log of all executed stock actions."""
    cid = x_company_id or "default"
    return {"action_ledger": db_instance._get_company(cid)["action_ledger"]}

@app.post("/api/cache/clear")
def clear_cache():
    cache_manager.clear()
    semantic_cache.clear()
    return {"status": "success", "message": "Cache cleared successfully"}

@app.get("/api/cache/stats")
def get_cache_stats():
    """
    Returns metrics on semantic and persistent cache hit rates, entry counts, and configuration.
    """
    return {
        "status": "success",
        "vector_semantic_cache": semantic_cache.get_stats(),
        "persistent_cache": cache_manager.get_stats()
    }


from agent_swarm import AutonomousSwarm

swarm_instance = AutonomousSwarm(db=db_instance)

class SwarmEventRequest(BaseModel):
    event_name: str
    payload: Dict[str, Any] = {}

class SwarmQueryRequest(BaseModel):
    query: str

class GuardrailValidationRequest(BaseModel):
    action_type: str
    payload: Dict[str, Any]
    barcode: Optional[str] = None

@app.post("/api/swarm/trigger")
def trigger_swarm_event(request: SwarmEventRequest):
    """
    Triggers an autonomous background event loop in the multi-agent swarm.
    """
    res = swarm_instance.process_event_trigger(request.event_name, request.payload)
    return {"status": "success", "result": res}

@app.post("/api/swarm/autopilot")
def run_swarm_autopilot(x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Triggers full 24/7 background autopilot sweep across all sub-agents (Reorder, Decay/Idle, Supplier Watch).
    """
    res = swarm_instance.run_full_autopilot_sweep()
    return {"status": "success", "sweep_results": res, "pending_pos": swarm_instance.pending_pos}

@app.get("/api/swarm/logs")
def get_swarm_logs():
    """
    Returns episodic memory audit log of all autonomous decision logs.
    """
    return {
        "status": "success",
        "episodic_memory": swarm_instance.episodic_memory,
        "pending_pos": swarm_instance.pending_pos
    }

class POApprovalRequest(BaseModel):
    po_id: str

@app.post("/api/swarm/approve_po")
def approve_pending_po_endpoint(request: POApprovalRequest):
    """
    1-Click Human Approval for queued high-value Purchase Orders.
    """
    res = swarm_instance.approve_pending_po(request.po_id)
    return res

@app.post("/api/swarm/query")
def query_swarm(request: SwarmQueryRequest):
    """
    Ultra-fast query processing via semantic cache and vectorized pandas code engine.
    """
    res = swarm_instance.process_query(request.query)
    return {"status": "success", "result": res}


@app.post("/api/guardrails/validate")
def validate_guardrails(request: GuardrailValidationRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Evaluates business policy compliance, spending caps, and safety guardrails on an action payload.
    """
    cid = x_company_id or "default"
    item = db_instance.get_product(request.barcode, company_id=cid) if request.barcode else None
    res = swarm_instance.guardrails.validate_action(request.action_type, request.payload, item)
    return {
        "status": "success",
        "passed": res.passed,
        "requires_human_approval": res.requires_human_approval,
        "risk_level": res.risk_level,
        "reasons": res.reasons,
        "sanitized_payload": res.sanitized_payload
    }

class InventorySyncRequest(BaseModel):
    products: List[Dict[str, Any]]

@app.post("/api/inventory/sync")
def sync_inventory_endpoint(request: InventorySyncRequest, x_company_id: Optional[str] = Header(None, alias="x-company-id")):
    """
    Syncs live user inventory items from the client app into the AI engine's real-time dataset.
    """
    cid = x_company_id or "default"
    if request.products:
        db_instance.replace_user_inventory(request.products, company_id=cid)
        semantic_cache.clear()
    return {"status": "success", "synced_items_count": len(db_instance.get_all_products(company_id=cid))}

@app.get("/health")
def health_check():
    return {"status": "ok", "mode": "Autonomous Self-Sufficient AI Agent Engine"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)


