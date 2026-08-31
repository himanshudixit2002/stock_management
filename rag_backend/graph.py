"""Compiled agent graph.

Nodes are async: the LLM calls stream, and the blocking Firestore reads are
pushed off the event loop with `asyncio.to_thread`. Use `ainvoke`/`astream_events`
(`run_sync` is provided for scripts and tests that are not already async).
"""

import asyncio
from typing import Any, Dict

from langgraph.graph import END, StateGraph

from nodes import (
    analytics_agent_node,
    execution_agent_node,
    knowledge_agent_node,
    retrieve_node,
    router_node,
)
from state import GraphState


def route_intent(state: GraphState) -> str:
    intent = state.get("intent", "KNOWLEDGE")
    if intent == "EXECUTION":
        return "execution_agent"
    if intent == "ANALYTICS":
        return "analytics_agent"
    return "knowledge_agent"


workflow = StateGraph(GraphState)

workflow.add_node("router", router_node)
workflow.add_node("retrieve", retrieve_node)
workflow.add_node("execution_agent", execution_agent_node)
workflow.add_node("analytics_agent", analytics_agent_node)
workflow.add_node("knowledge_agent", knowledge_agent_node)

workflow.set_entry_point("router")
workflow.add_edge("router", "retrieve")
workflow.add_conditional_edges(
    "retrieve",
    route_intent,
    {
        "execution_agent": "execution_agent",
        "analytics_agent": "analytics_agent",
        "knowledge_agent": "knowledge_agent",
    },
)
workflow.add_edge("execution_agent", END)
workflow.add_edge("analytics_agent", END)
workflow.add_edge("knowledge_agent", END)

rag_pipeline = workflow.compile()


def run_sync(inputs: Dict[str, Any]) -> Dict[str, Any]:
    """Blocking entry point for scripts and tests."""
    return asyncio.run(rag_pipeline.ainvoke(inputs))
