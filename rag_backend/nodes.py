import json
import re
from pydantic import BaseModel, Field
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.prompts import ChatPromptTemplate
from state import GraphState

# 1. Structured Tool Schema
class UpdateStock(BaseModel):
    product_name: str = Field(description="The name of the product to update.")
    barcode: str = Field(description="The exact alphanumeric barcode of the product extracted from the context.")
    qty_change: int = Field(description="The exact quantity to add (positive) or deduct (negative).")

# 2. Specialized System Prompts
lite_prompt = ChatPromptTemplate.from_messages([
    ("system", "You are the automated inventory ledger for SmartShelfKart. Your ONLY task is tool execution.\n\n"
               "CRITICAL DATABASE SCHEMA:\n"
               "- product_name (string)\n"
               "- barcode (string)\n"
               "- current_stock (integer)\n\n"
               "RULES:\n"
               "1. Match the user's requested item to the context, extract the exact barcode, and call the UpdateStock tool. Do not guess.\n"
               "2. If the barcode is missing, output exactly one short sentence asking for it (e.g., 'Please provide the barcode for [Product].').\n"
               "3. NO conversational filler. NO greetings."),
    ("user", "Context: {context}\nQuestion: {question}\nAssistant:")
])

pro_prompt = ChatPromptTemplate.from_messages([
    ("system", "You are Nova, Chief Supply Chain & Inventory Intelligence Strategist for SmartShelfKart.\n\n"
               "CRITICAL RULES FOR EXTRAORDINARY RESPONSES:\n"
               "1. EXTRAORDINARY STRATEGIC INSIGHT: Do NOT give generic, predictable answers or repetitive intros (never say 'Here is your summary' or 'Based on context'). Deliver deep executive-level intelligence.\n"
               "2. THREE-PILLAR STRUCTURE when answering:\n"
               "   • 📈 **Strategic Velocity**: Sharp snapshot of current stock health/metrics.\n"
               "   • 🚨 **Risk & Revenue Exposure**: Urgent bottlenecks, out-of-stock threats, or order imbalances.\n"
               "   • ⚡ **Executive Blueprint**: Highly tactical reorder or stock management recommendation.\n"
               "3. FACTUAL GROUNDING: Be 100% truthful to numbers in context. Never hallucinate quantities or barcodes.\n"
               "4. BREVITY & VISUAL IMPACT: Keep under 5 punchy sentences total. Use bold metrics, short bullet points, and clean markdown tables for comparisons.\n"
               "5. You DO NOT have direct stock edit tools in this mode. Answer strictly using context."),
    ("user", "Context: {context}\nQuestion: {question}\nAssistant:")
])

# 3. Model & Chain Initialization
llm_lite = ChatGoogleGenerativeAI(model="gemini-3.1-flash-lite", temperature=0)
llm_pro = ChatGoogleGenerativeAI(model="gemini-3.5-flash", temperature=0.3)

llm_lite_with_tools = llm_lite.bind_tools([UpdateStock])

# 4. Data Layer Retrieval
def get_retriever():
    embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2")
    vectorstore = Chroma(
        collection_name="stock_inventory",
        embedding_function=embeddings,
        persist_directory="./chroma_db"
    )
    return vectorstore.as_retriever(search_kwargs={"k": 3})

def retrieve(state: GraphState):
    question = state["question"]
    provided_context = state.get("provided_context")

    if provided_context:
        documents = [Document(page_content=provided_context)]
    else:
        try:
            retriever = get_retriever()
            documents = retriever.invoke(question)
        except Exception:
            documents = []
    
    return {"documents": documents, "question": question}

# 5. Core Operational Brain
def generate(state: GraphState):
    question = state["question"]
    documents = state["documents"]
    history = state.get("history") or []
    
    docs_text = "\n\n".join(doc.page_content for doc in documents) if documents else "No inventory context available."
    
    q_lower = question.lower()
    analytics_keywords = ["analyze", "forecast", "trend", "predict", "growth", "report", "summary", "why"]
    operation_keywords = ["update", "add", "remove", "deduct", "stock", "change"]
    
    is_analytics = any(kw in q_lower for kw in analytics_keywords)
    has_operation = any(kw in q_lower for kw in operation_keywords)
    
    is_simple_update = has_operation and not is_analytics
    
    from langchain_core.messages import SystemMessage, HumanMessage, AIMessage
    
    messages = []
    if is_simple_update:
        messages.append(SystemMessage(content=(
            "You are the automated inventory ledger for SmartShelfKart. Your ONLY task is tool execution.\n\n"
            "CRITICAL DATABASE SCHEMA:\n"
            "- product_name (string)\n"
            "- barcode (string)\n"
            "- current_stock (integer)\n\n"
            "RULES:\n"
            "1. Match the user's requested item to the context, extract the exact barcode, and call the UpdateStock tool. Do not guess.\n"
            "2. If the barcode is missing, output exactly one short sentence asking for it (e.g., 'Please provide the barcode for [Product].').\n"
            "3. NO conversational filler, NO greetings, NO explanations."
        )))
    else:
        messages.append(SystemMessage(content=(
            "You are Nova, Chief Supply Chain & Inventory Intelligence Strategist for SmartShelfKart.\n\n"
            "CRITICAL RULES FOR EXTRAORDINARY RESPONSES:\n"
            "1. EXTRAORDINARY STRATEGIC INSIGHT: Do NOT give generic, predictable answers or repetitive intros (never say 'Here is your summary' or 'Based on context'). Deliver deep executive-level intelligence.\n"
            "2. THREE-PILLAR STRUCTURE when answering:\n"
            "   • 📈 **Strategic Velocity**: Sharp snapshot of current stock health/metrics.\n"
            "   • 🚨 **Risk & Revenue Exposure**: Urgent bottlenecks, out-of-stock threats, or order imbalances.\n"
            "   • ⚡ **Executive Blueprint**: Highly tactical reorder or stock management recommendation.\n"
            "3. FACTUAL GROUNDING: Answer ONLY based on context numbers. If context is missing, state 'No matching inventory records found.'\n"
            "4. BREVITY & VISUAL IMPACT: Keep under 5 punchy sentences total. Use bold metrics, short bullet points, and markdown tables for comparisons."
        )))
        
    for msg in history:
        role = msg.get("role")
        content = msg.get("content", "")
        if role == "user":
            messages.append(HumanMessage(content=content))
        elif role in ["assistant", "model"]:
            messages.append(AIMessage(content=content))
            
    messages.append(HumanMessage(content=f"Context: {docs_text}\nQuestion: {question}"))
    
    try:
        if is_simple_update:
            response = llm_lite_with_tools.invoke(messages)
        else:
            response = llm_pro.invoke(messages)
    except Exception as e:
        print(f"LLM Error: {e}")
        return {"documents": documents, "question": question, "generation": "I am currently experiencing connection issues with my AI brain. Please try again later."}
    
    if hasattr(response, "tool_calls") and response.tool_calls:
        tool_call = response.tool_calls[0]
        if tool_call["name"] == "UpdateStock":
            args = tool_call["args"]
            product_name = args.get("product_name", "")
            qty = args.get("qty_change", 0)
            barcode = args.get("barcode", "")
            
            if not barcode or barcode == product_name:
                return {"documents": documents, "question": question, "generation": f"Could you please provide the exact barcode for {product_name}?"}
            
            action_json = json.dumps({
                "type": "update_stock", 
                "barcode": barcode, 
                "qty_change": qty
            })
            generation = f"📦 Stock adjustment prepared for {product_name} (Barcode: {barcode}).\n\n[ACTION: {action_json}]"
            return {"documents": documents, "question": question, "generation": generation}
    
    generation = response.content
    
    if isinstance(generation, list):
        text_blocks = []
        for block in generation:
            if isinstance(block, dict) and "text" in block:
                text_blocks.append(block["text"])
            elif isinstance(block, str):
                text_blocks.append(block)
        generation = "".join(text_blocks)
    elif not isinstance(generation, str):
        generation = str(generation)
        
    if not generation.strip():
        generation = "✅ Request processed successfully."
        
    return {"documents": documents, "question": question, "generation": generation}

