from typing import List, TypedDict, Optional, Dict

class GraphState(TypedDict):
    """
    Represents the state of our graph for Stock Recommendations.
    """
    question: str
    generation: str
    documents: List[str]
    retries: int
    is_restock_required: Optional[bool]
    provided_context: Optional[str]
    history: Optional[List[Dict[str, str]]]

