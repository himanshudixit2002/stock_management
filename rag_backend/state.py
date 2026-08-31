from typing import Any, Dict, List, Optional, TypedDict


class GraphState(TypedDict, total=False):
    """State threaded through the inventory agent graph."""

    # --- request ---
    question: str
    history: Optional[List[Dict[str, str]]]
    provided_context: Optional[str]
    company_id: str
    business_type: str
    session_id: str

    # --- routing ---
    intent: str          # EXECUTION | ANALYTICS | KNOWLEDGE
    route_source: str    # regex | llm | pending | cache
    retries: int

    # --- facts (the single source of truth for this turn) ---
    facts: Any                    # InventoryFacts
    context_block: str            # rendered prompt context
    focus: List[Any]              # ProductFacts the question is about

    # --- output ---
    generation: str
    executed_actions: List[Dict[str, Any]]
    analytics_data: Optional[Dict[str, Any]]
    structured_payload: Optional[Dict[str, Any]]

    # --- how the client should render this answer ---
    # preview | clarification | product_detail | report | no_history |
    # executed | prose
    response_kind: str

    # --- confirmation flow ---
    pending_action: Optional[Dict[str, Any]]
    clarification_options: Optional[List[Dict[str, Any]]]

    # --- telemetry ---
    answered_by: str     # deterministic | llm | pending | fallback
    llm_calls: int
