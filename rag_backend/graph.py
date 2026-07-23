from langgraph.graph import END, StateGraph
from state import GraphState
from nodes import (
    router_node,
    retrieve_node,
    action_agent_node,
    analytics_agent_node,
    knowledge_agent_node
)

def route_intent(state: GraphState) -> str:
    """Conditional edge router based on evaluated intent."""
    intent = state.get("intent", "KNOWLEDGE")
    if intent == "ACTION":
        return "action_agent"
    elif intent == "ANALYTICS":
        return "analytics_agent"
    else:
        return "knowledge_agent"

workflow = StateGraph(GraphState)

# Add nodes
workflow.add_node("router", router_node)
workflow.add_node("retrieve", retrieve_node)
workflow.add_node("action_agent", action_agent_node)
workflow.add_node("analytics_agent", analytics_agent_node)
workflow.add_node("knowledge_agent", knowledge_agent_node)

# Set entry point
workflow.set_entry_point("router")
workflow.add_edge("router", "retrieve")

# Add conditional routing edges
workflow.add_conditional_edges(
    "retrieve",
    route_intent,
    {
        "action_agent": "action_agent",
        "analytics_agent": "analytics_agent",
        "knowledge_agent": "knowledge_agent"
    }
)

workflow.add_edge("action_agent", END)
workflow.add_edge("analytics_agent", END)
workflow.add_edge("knowledge_agent", END)

# Compile graph pipeline
rag_pipeline = workflow.compile()
