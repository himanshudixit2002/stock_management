from langgraph.graph import END, StateGraph
from state import GraphState
from nodes import classify_intent, smart_retrieve, generate, grade_documents, grade_hallucination, format_response

workflow = StateGraph(GraphState)

workflow.add_node("classify_intent", classify_intent)
workflow.add_node("smart_retrieve", smart_retrieve)
workflow.add_node("generate", generate)
workflow.add_node("grade_documents", grade_documents)
workflow.add_node("grade_hallucination", grade_hallucination)
workflow.add_node("format_response", format_response)

workflow.set_entry_point("classify_intent")

def route_after_classification(state):
    if state["intent"] in ["GREETING", "NAVIGATION"]:
        return "format_response"
    return "smart_retrieve"

workflow.add_conditional_edges("classify_intent", route_after_classification, {
    "format_response": "format_response",
    "smart_retrieve": "smart_retrieve"
})

workflow.add_edge("smart_retrieve", "generate")
workflow.add_edge("generate", "grade_documents")

def route_after_grade_docs(state):
    if state["doc_grade"] == "relevant" or state["intent"] in ["GREETING", "NAVIGATION"]:
        return "grade_hallucination"
    if state.get("retries", 0) < state.get("max_retries", 2):
        state["retries"] = state.get("retries", 0) + 1
        return "smart_retrieve"
    return "format_response"
    
workflow.add_conditional_edges("grade_documents", route_after_grade_docs, {
    "grade_hallucination": "grade_hallucination",
    "smart_retrieve": "smart_retrieve",
    "format_response": "format_response"
})

def route_after_grade_hallucination(state):
    if state["hallucination_grade"] == "grounded" or state["intent"] in ["GREETING", "NAVIGATION"]:
        return "format_response"
    if state.get("retries", 0) < state.get("max_retries", 2):
        state["retries"] = state.get("retries", 0) + 1
        return "generate"
    return "format_response"

workflow.add_conditional_edges("grade_hallucination", route_after_grade_hallucination, {
    "format_response": "format_response",
    "generate": "generate"
})

workflow.add_edge("format_response", END)

rag_pipeline = workflow.compile()

