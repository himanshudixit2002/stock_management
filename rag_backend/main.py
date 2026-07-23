from typing import Optional, List
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
from dotenv import load_dotenv
load_dotenv()

from fastapi.middleware.cors import CORSMiddleware
from graph import rag_pipeline
from cache_manager import CacheManager

app = FastAPI(title="Self-Healing RAG API")
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
    retries: int

@app.post("/api/chat", response_model=QueryResponse)
async def chat_endpoint(request: QueryRequest):
    history_list = [h.model_dump() for h in request.history] if request.history else []
    
    # 1. Check cache
    cached_generation = cache_manager.get(request.question, request.context, history_list)
    if cached_generation:
        return QueryResponse(
            answer=cached_generation,
            retries=0
        )
    
    # 2. Cache miss: invoke LangGraph
    inputs = {
        "question": request.question, 
        "retries": 0,
        "provided_context": request.context,
        "history": history_list
    }
    # Invoke the LangGraph pipeline
    final_state = rag_pipeline.invoke(inputs)
    generation = final_state["generation"]
    
    # 3. Store in cache if not a connection error
    if "connection issues" not in generation:
        cache_manager.set(request.question, request.context, history_list, generation)
    
    return QueryResponse(
        answer=generation,
        retries=final_state.get("retries", 0)
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
    from ingest import ingest_custom_products
    prods = [p.model_dump() for p in request.products]
    ingest_custom_products(prods)
    cache_manager.clear()
    return {"status": "success", "message": f"Ingested {len(prods)} products into ChromaDB vectorstore"}

@app.post("/api/cache/clear")
def clear_cache():
    cache_manager.clear()
    return {"status": "success", "message": "Cache cleared successfully"}

@app.get("/health")
def health_check():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)

