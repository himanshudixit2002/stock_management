from typing import Optional
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
from dotenv import load_dotenv
load_dotenv()

from fastapi.middleware.cors import CORSMiddleware
from graph import rag_pipeline

app = FastAPI(title="Self-Healing RAG API")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class QueryRequest(BaseModel):
    question: str
    context: Optional[str] = None

class QueryResponse(BaseModel):
    answer: str
    retries: int

@app.post("/api/chat", response_model=QueryResponse)
async def chat_endpoint(request: QueryRequest):
    inputs = {
        "question": request.question, 
        "retries": 0,
        "provided_context": request.context
    }
    # Invoke the LangGraph pipeline
    final_state = rag_pipeline.invoke(inputs)
    
    return QueryResponse(
        answer=final_state["generation"],
        retries=final_state.get("retries", 0)
    )

@app.get("/health")
def health_check():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
