from typing import List, TypedDict, Optional
from langchain_core.documents import Document


class GraphState(TypedDict):
    """State for the self-healing RAG pipeline."""
    question: str
    chat_history: List[dict]          # [{role: 'user'|'assistant', content: str}, ...]
    intent: str                        # classified intent category
    generation: str
    documents: List[Document]          # Retrieved/provided context documents
    retries: int
    max_retries: int                   # default 2
    doc_grade: str                     # 'relevant' | 'irrelevant'
    hallucination_grade: str           # 'grounded' | 'hallucinated'
    provided_context: Optional[str]
    action_payload: Optional[dict]     # Structured action output
