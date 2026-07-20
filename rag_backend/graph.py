from langgraph.graph import END, StateGraph
from state import GraphState
from nodes import retrieve, generate

workflow = StateGraph(GraphState)

# Define the nodes
workflow.add_node("retrieve", retrieve)
workflow.add_node("generate", generate)

# Build graph
workflow.set_entry_point("retrieve")
workflow.add_edge("retrieve", "generate")
workflow.add_edge("generate", END)

# Compile the graph
rag_pipeline = workflow.compile()
