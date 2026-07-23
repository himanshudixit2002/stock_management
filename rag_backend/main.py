from typing import Optional, List, Dict, Any
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
from dotenv import load_dotenv
load_dotenv()

from fastapi.middleware.cors import CORSMiddleware
from graph import rag_pipeline
from cache_manager import CacheManager
from inventory_db import db_instance

app = FastAPI(
    title="Action-Oriented AI Stock Management API",
    description="Autonomous Agentic AI Engine for Real-Time Inventory Control and Decisioning"
)
cache_manager = CacheManager()

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

class QueryResponse(BaseModel):
    answer: str
    retries: int = 0
    intent: Optional[str] = "KNOWLEDGE"
    executed_actions: Optional[List[Dict[str, Any]]] = []
    analytics_data: Optional[Dict[str, Any]] = None

@app.post("/api/chat", response_model=QueryResponse)
async def chat_endpoint(request: QueryRequest):
    history_list = [h.model_dump() for h in request.history] if request.history else []
    
    # Check cache only for simple knowledge queries
    # Actions & Analytics must always execute live!
    inputs = {
        "question": request.question, 
        "retries": 0,
        "provided_context": request.context,
        "history": history_list
    }

    # Invoke multi-agent pipeline
    final_state = rag_pipeline.invoke(inputs)
    generation = final_state.get("generation", "No response generated.")
    intent = final_state.get("intent", "KNOWLEDGE")
    executed_actions = final_state.get("executed_actions", [])
    analytics_data = final_state.get("analytics_data")
    
    return QueryResponse(
        answer=generation,
        retries=final_state.get("retries", 0),
        intent=intent,
        executed_actions=executed_actions,
        analytics_data=analytics_data
    )

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
async def ingest_endpoint(request: ProductIngestRequest):
    prods = [p.model_dump() for p in request.products]
    for p in prods:
        db_instance.upsert_product(p)
    
    # Also index into ChromaDB if available
    try:
        from ingest import ingest_custom_products
        ingest_custom_products(prods)
    except Exception as e:
        print(f"Vector ingest warning: {e}")
        
    cache_manager.clear()
    return {"status": "success", "message": f"Ingested {len(prods)} products into live inventory database & vectorstore."}

@app.get("/api/agent/autopilot")
def autopilot_scan():
    """
    Proactively scans inventory levels, calculates reorder point requirements based on sales velocity and lead times,
    and returns automated purchase recommendations.
    """
    recommendations = db_instance.run_autopilot_scan()
    metrics = db_instance.get_analytics_summary()
    return {
        "status": "success",
        "timestamp": metrics,
        "recommendations_count": len(recommendations),
        "recommendations": recommendations
    }

@app.get("/api/inventory")
def get_inventory():
    """Returns list of all products in the live inventory database."""
    return {"products": db_instance.get_all_products()}

@app.get("/api/inventory/ledger")
def get_inventory_ledger():
    """Returns audit log of all executed stock actions."""
    return {"action_ledger": db_instance.action_ledger}

@app.post("/api/cache/clear")
def clear_cache():
    cache_manager.clear()
    return {"status": "success", "message": "Cache cleared successfully"}

@app.get("/health")
def health_check():
    return {"status": "ok", "mode": "Action-Oriented Autonomous Agent"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
