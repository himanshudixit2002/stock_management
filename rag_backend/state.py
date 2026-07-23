from typing import List, TypedDict, Optional, Dict, Any

class GraphState(TypedDict):
    """
    Represents the state of our Action-Oriented AI Graph for Stock Management.
    """
    question: str
    generation: str
    documents: List[Any]
    retries: int
    is_restock_required: Optional[bool]
    provided_context: Optional[str]
    history: Optional[List[Dict[str, str]]]
    
    # Action-Oriented AI extensions
    intent: Optional[str]  # ACTION, ANALYTICS, KNOWLEDGE
    executed_actions: Optional[List[Dict[str, Any]]]
    analytics_data: Optional[Dict[str, Any]]
    structured_payload: Optional[Dict[str, Any]]
