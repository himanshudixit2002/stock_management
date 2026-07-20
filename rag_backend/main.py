import asyncio
import time
import logging
import json
import re
from typing import Optional, List
from fastapi import FastAPI, Request
from pydantic import BaseModel, Field
import uvicorn
from dotenv import load_dotenv
load_dotenv()

from fastapi.middleware.cors import CORSMiddleware
from graph import rag_pipeline
from cache import get_cached, set_cached, should_cache

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# NOTE for deployment: Recommend setting min_instances: 1 in Cloud Run 
# to avoid cold start issues with heavy LLM imports.
app = FastAPI(title="Self-Healing RAG API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    question: str = Field(max_length=2000)
    context: Optional[str] = Field(default=None, max_length=50000)
    chat_history: List[dict] = Field(default_factory=list)
    stream: bool = False

class ChatResponse(BaseModel):
    answer: str
    intent: str = ''
    action: Optional[dict] = None
    retries: int = 0
    cached: bool = False
    latency_ms: int = 0

@app.post("/api/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    start_time = time.time()
    
    cached_resp = get_cached(request.question, request.context or "")
    if cached_resp:
        logger.info("Cache hit")
        return ChatResponse(**cached_resp, latency_ms=int((time.time() - start_time) * 1000))
        
    inputs = {
        "question": request.question,
        "provided_context": request.context,
        "chat_history": request.chat_history,
        "retries": 0,
        "max_retries": 2
    }
    
    try:
        final_state = await asyncio.wait_for(asyncio.to_thread(rag_pipeline.invoke, inputs), timeout=55.0)
    except asyncio.TimeoutError:
        logger.error("RAG pipeline timed out after 55s")
        return ChatResponse(
            answer="I'm sorry, this request took too long to process. Please try again.",
            intent="ERROR",
            latency_ms=int((time.time() - start_time) * 1000)
        )
    except Exception as e:
        logger.error(f"RAG pipeline error: {e}")
        return ChatResponse(
            answer="I'm sorry, I encountered an error processing your request.",
            intent="ERROR",
            latency_ms=int((time.time() - start_time) * 1000)
        )
    
    answer = final_state.get("generation", "")
    action = final_state.get("action_payload")
    
    if not action:
        action_match = re.search(r'\[ACTION:\s*({.*?})\s*\]', answer, re.DOTALL)
        if action_match:
            try:
                action = json.loads(action_match.group(1))
                answer = answer.replace(action_match.group(0), "").strip()
            except json.JSONDecodeError:
                pass
                
    resp_dict = {
        "answer": answer,
        "intent": final_state.get("intent", "GENERAL"),
        "action": action,
        "retries": final_state.get("retries", 0),
        "cached": False,
        "latency_ms": int((time.time() - start_time) * 1000)
    }
    
    if should_cache(resp_dict["intent"]):
        set_cached(request.question, request.context or "", resp_dict)
        
    return ChatResponse(**resp_dict)

@app.get("/warmup")
async def warmup_endpoint():
    """Cloud Run startup probe endpoint."""
    return {"status": "ok"}

@app.get("/health")
def health_check():
    return {"status": "ok", "version": "2.1"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)

