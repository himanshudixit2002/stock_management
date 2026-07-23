import json
import os
import re
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from dotenv import load_dotenv

# Load env variables from current directory or parent directory
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage

from state import GraphState
from inventory_db import db_instance

def extract_text_content(content: Any) -> str:
    """Helper to safely extract string text from langchain response content."""
    if isinstance(content, str):
        return content
    elif isinstance(content, list):
        text_parts = []
        for part in content:
            if isinstance(part, str):
                text_parts.append(part)
            elif isinstance(part, dict):
                if "text" in part:
                    text_parts.append(part["text"])
            elif hasattr(part, "get") and part.get("text"):
                text_parts.append(part.get("text"))
            elif hasattr(part, "text") and part.text:
                text_parts.append(part.text)
        return "".join(text_parts)
    return str(content)

# ---------------------------------------------------------
# 1. Action Tool Schemas
# ---------------------------------------------------------

class UpdateStock(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item to update.")
    qty_change: int = Field(description="The quantity to add (positive integer) or deduct (negative integer).")
    reason: Optional[str] = Field(default="Manual Adjustment", description="Reason for stock adjustment.")

class CreatePurchaseOrder(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item to reorder.")
    reorder_qty: int = Field(description="Quantity to reorder from supplier.")
    supplier_name: Optional[str] = Field(default="Default Supplier", description="Name of supplier/vendor.")

class TransferStock(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item to transfer.")
    from_location: str = Field(description="Source location e.g. Store Front or Warehouse B.")
    to_location: str = Field(description="Target destination location.")
    qty: int = Field(description="Quantity of units to move.")

class AuditInventory(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item audited.")
    actual_stock: int = Field(description="Physical counted stock quantity.")
    notes: Optional[str] = Field(default="Physical Audit", description="Audit observation notes e.g. damaged goods.")

class SetReorderAlert(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item.")
    new_min_threshold: int = Field(description="New minimum safety stock threshold.")

# ---------------------------------------------------------
# 2. LLM Initialization & Tool Binding
# ---------------------------------------------------------

api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or "MOCK_KEY_FOR_INIT"

llm_action = ChatGoogleGenerativeAI(model="gemini-3.1-flash-lite", temperature=0, google_api_key=api_key)
llm_pro = ChatGoogleGenerativeAI(model="gemini-3.5-flash", temperature=0.2, google_api_key=api_key)

ACTION_TOOLS = [UpdateStock, CreatePurchaseOrder, TransferStock, AuditInventory, SetReorderAlert]
llm_action_with_tools = llm_action.bind_tools(ACTION_TOOLS)

# ---------------------------------------------------------
# 3. Vectorstore Retriever
# ---------------------------------------------------------

def get_retriever():
    embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2", google_api_key=api_key)
    vectorstore = Chroma(
        collection_name="stock_inventory",
        embedding_function=embeddings,
        persist_directory="./chroma_db"
    )
    return vectorstore.as_retriever(search_kwargs={"k": 3})

# ---------------------------------------------------------
# 4. Multi-Agent Graph Nodes
# ---------------------------------------------------------

def router_node(state: GraphState) -> GraphState:
    """Classifies user intent into ACTION, ANALYTICS, or KNOWLEDGE using word-boundary matching."""
    question = state["question"].lower()
    
    action_keywords = [r"\bupdate\b", r"\badd\b", r"\bdeduct\b", r"\bremove\b", r"\breorder\b", r"\bpo\b", r"\bpurchase order\b", r"\btransfer\b", r"\bmove\b", r"\baudit\b", r"\bset threshold\b", r"\balert\b"]
    analytics_keywords = [r"\banalyze\b", r"\bforecast\b", r"\btrend\b", r"\bpredict\b", r"\bgrowth\b", r"\breport\b", r"\bsummary\b", r"\bstats\b", r"\bmetrics\b", r"\btop\b", r"\blow stock\b", r"\bout of stock\b", r"\bvaluation\b"]
    
    is_action = any(re.search(kw, question) for kw in action_keywords)
    is_analytics = any(re.search(kw, question) for kw in analytics_keywords)
    
    if is_action:
        intent = "ACTION"
    elif is_analytics:
        intent = "ANALYTICS"
    else:
        intent = "KNOWLEDGE"
        
    state["intent"] = intent
    return state

def retrieve_node(state: GraphState) -> GraphState:
    """Retrieves vector context AND pulls live database records."""
    question = state["question"]
    provided_context = state.get("provided_context")

    if provided_context and "[REAL_USER_CATALOG:" in provided_context:
        try:
            match = re.search(r'\[REAL_USER_CATALOG:\s*(\[.*?\])\s*\]', provided_context, re.DOTALL)
            if match:
                catalog_list = json.loads(match.group(1))
                if isinstance(catalog_list, list) and catalog_list:
                    db_instance.replace_user_inventory(catalog_list)
        except Exception as e:
            print(f"Error loading user catalog into DB: {e}")

    documents = []
    if provided_context:
        documents.append(Document(page_content=provided_context))
    else:
        try:
            if api_key != "MOCK_KEY_FOR_INIT":
                retriever = get_retriever()
                documents = retriever.invoke(question)
        except Exception:
            pass

    # Always enrich with live DB state
    all_products = db_instance.get_all_products()
    db_context_str = "LIVE USER INVENTORY DATABASE RECORDS:\n" + "\n".join([
        f"- Product: {p['name']} | Barcode: {p['barcode']} | Stock: {p['stock']} | Min Threshold: {p['min_threshold']} | Category: {p.get('category', 'General')} | Location: {p.get('location', 'Main Store')}"
        for p in all_products
    ])
    documents.append(Document(page_content=db_context_str))

    state["documents"] = documents
    return state

def _fallback_rule_matcher(question: str) -> Optional[Dict[str, Any]]:
    """Fallback action tool matcher when running offline or without an active API key."""
    q = question.lower()
    all_prods = db_instance.get_all_products()
    
    # Try finding matching product in question
    target_product = None
    for p in all_prods:
        if p["barcode"] in question or p["name"].lower() in q:
            target_product = p
            break
            
    if not target_product and all_prods:
        target_product = all_prods[0] # Default to first product if unspecified
        
    if not target_product:
        return None

    # Detect update stock
    nums = re.findall(r'\b\d+\b', question)
    qty = int(nums[0]) if nums else 10

    if any(k in q for k in ["add", "increase", "update", "restock"]):
        res = db_instance.update_stock(target_product["barcode"], qty, "Rule Action")
        return {"tool": "UpdateStock", "res": res, "qty": qty}
    elif any(k in q for k in ["deduct", "remove", "reduce", "minus"]):
        res = db_instance.update_stock(target_product["barcode"], -qty, "Rule Action")
        return {"tool": "UpdateStock", "res": res, "qty": -qty}
    elif any(k in q for k in ["reorder", "po", "purchase order"]):
        res = db_instance.create_purchase_order(target_product["barcode"], qty, "Auto Supplier")
        return {"tool": "CreatePurchaseOrder", "res": res, "qty": qty}
        
    return None

def action_agent_node(state: GraphState) -> GraphState:
    """Executes tools against live Inventory DB and logs ledger mutations."""
    question = state["question"]
    documents = state["documents"]
    history = state.get("history") or []
    
    context_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))

    executed_actions = []
    
    # Check if real API Key is available
    if api_key == "MOCK_KEY_FOR_INIT":
        # Rule-based fallback tool execution
        fallback_res = _fallback_rule_matcher(question)
        if fallback_res:
            tool_name = fallback_res["tool"]
            res = fallback_res["res"]
            executed_actions.append({"tool": tool_name, "result": res})
            if res.get("success"):
                p = res.get("product", {})
                if tool_name == "UpdateStock":
                    generation = f"⚡ **{p.get('name')}** (BC: `{p.get('barcode')}`): Stock updated {res['old_stock']} ➡️ **{res['new_stock']}** units! 📦"
                elif tool_name == "CreatePurchaseOrder":
                    generation = f"📦 **PO {res['po_id']}** created: Reordered **{res['reorder_qty']}** units of **{p.get('name')}** (Est. Cost: **${res['total_cost']:.2f}**)! 💳"
                else:
                    generation = f"✅ Action processed successfully for {p.get('name')}."
            else:
                generation = f"❌ Action failed: {res.get('error')}"
        else:
            generation = f"⚠️ Please set your GOOGLE_API_KEY in `rag_backend/.env` to enable full LLM function calling."
            
        state["executed_actions"] = executed_actions
        state["generation"] = generation
        return state

    system_prompt = (
        "You are the Action Execution Agent for SmartShelfKart Inventory Ledger.\n"
        "Your role is to extract arguments and invoke the correct tool:\n"
        "- UpdateStock(barcode_or_name, qty_change, reason)\n"
        "- CreatePurchaseOrder(barcode_or_name, reorder_qty, supplier_name)\n"
        "- TransferStock(barcode_or_name, from_location, to_location, qty)\n"
        "- AuditInventory(barcode_or_name, actual_stock, notes)\n"
        "- SetReorderAlert(barcode_or_name, new_min_threshold)\n\n"
        "DATABASE SCHEMA Context:\n" + context_text + "\n\n"
        "RULES:\n"
        "1. Select the exact product barcode or name from context.\n"
        "2. If missing parameters, output a short single-sentence clarification request.\n"
        "3. NO conversational filler."
    )

    messages = [SystemMessage(content=system_prompt)]
    for msg in history:
        r = msg.get("role")
        c = msg.get("content", "")
        if r == "user":
            messages.append(HumanMessage(content=c))
        elif r in ["assistant", "model"]:
            messages.append(AIMessage(content=c))
    messages.append(HumanMessage(content=question))

    try:
        response = llm_action_with_tools.invoke(messages)
    except Exception as e:
        state["generation"] = f"Action Execution Error: {str(e)}"
        return state

    if hasattr(response, "tool_calls") and response.tool_calls:
        for tool_call in response.tool_calls:
            t_name = tool_call["name"]
            args = tool_call["args"]
            target = args.get("barcode_or_name", "")

            if t_name == "UpdateStock":
                res = db_instance.update_stock(target, args.get("qty_change", 0), args.get("reason", "API Action"))
                executed_actions.append({"tool": "UpdateStock", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"⚡ **{p['name']}** (BC: `{p['barcode']}`): Stock updated {res['old_stock']} ➡️ **{res['new_stock']}** units! 📦"
                else:
                    generation = f"❌ Stock update failed: {res.get('error')}"

            elif t_name == "CreatePurchaseOrder":
                res = db_instance.create_purchase_order(target, args.get("reorder_qty", 10), args.get("supplier_name", "Default Supplier"))
                executed_actions.append({"tool": "CreatePurchaseOrder", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"📦 **PO {res['po_id']}** created: Reordered **{res['reorder_qty']}** units of **{p['name']}** from **{res['supplier']}** (Est. Cost: **${res['total_cost']:.2f}**)! 💳"
                else:
                    generation = f"❌ Purchase order creation failed: {res.get('error')}"

            elif t_name == "TransferStock":
                res = db_instance.transfer_stock(target, args.get("from_location", "Main Store"), args.get("to_location", "Warehouse"), args.get("qty", 1))
                executed_actions.append({"tool": "TransferStock", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"🚚 **{p['name']}**: Transferred **{res['qty']}** units to **{res['to_location']}**! 📍"
                else:
                    generation = f"❌ Stock transfer failed: {res.get('error')}"

            elif t_name == "AuditInventory":
                res = db_instance.audit_inventory(target, args.get("actual_stock", 0), args.get("notes", "Physical Audit"))
                executed_actions.append({"tool": "AuditInventory", "result": res})
                if res.get("success"):
                    p = res["product"]
                    disc = res['discrepancy']
                    disc_str = f"+{disc}" if disc > 0 else f"{disc}"
                    generation = f"📋 **{p['name']}** Audited: Stock adjusted from {res['old_stock']} ➡️ **{res['actual_stock']}** (Diff: **{disc_str}**)! 🔍"
                else:
                    generation = f"❌ Audit logging failed: {res.get('error')}"

            elif t_name == "SetReorderAlert":
                res = db_instance.set_min_threshold(target, args.get("new_min_threshold", 10))
                executed_actions.append({"tool": "SetReorderAlert", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"🔔 **{p['name']}**: Safety threshold updated to **{res['new_threshold']}** units (was {res['old_threshold']})! ⚠️"
                else:
                    generation = f"❌ Threshold update failed: {res.get('error')}"

        state["executed_actions"] = executed_actions
        state["generation"] = generation
    else:
        content = extract_text_content(response.content)
        state["generation"] = content or "Execution finished with no tool calls."

    return state

def analytics_agent_node(state: GraphState) -> GraphState:
    """Calculates live analytics, stockout risks, and financial valuations from DB."""
    question = state["question"]
    metrics = db_instance.get_analytics_summary()
    autopilot_recs = db_instance.run_autopilot_scan()

    if api_key == "MOCK_KEY_FOR_INIT":
        content = (
            f"📊 **Inventory Analytics Summary**\n\n"
            f"| Metric 📈 | Value 🔢 |\n"
            f"| :--- | :--- |\n"
            f"| 📦 Registered Products | **{metrics['total_products']}** items |\n"
            f"| ⚠️ Low Stock Alerts | **{metrics['low_stock_count']}** warnings |\n"
            f"| 🚨 Out of Stock | **{metrics['out_of_stock_count']}** items |\n"
            f"| 💰 Valuation (Selling) | **${metrics['total_inventory_value']:,.2f}** |\n"
            f"| 💵 Valuation (Cost Basis) | **${metrics['total_cost_value']:,.2f}** |\n"
            f"| 🤖 Autopilot Restocks | **{len(autopilot_recs)}** suggestions |"
        )
    else:
        context_str = (
            f"INVENTORY METRICS SUMMARY:\n"
            f"- Total Products: {metrics['total_products']}\n"
            f"- Low Stock Count: {metrics['low_stock_count']}\n"
            f"- Out of Stock Count: {metrics['out_of_stock_count']}\n"
            f"- Total Selling Valuation: ${metrics['total_inventory_value']}\n"
            f"- Total Cost Valuation: ${metrics['total_cost_value']}\n"
            f"- Low Stock Products: {[p['name'] + ' (Stock: ' + str(p['stock']) + ')' for p in metrics['low_stock_items']]}\n"
            f"- Autopilot Reorder Recommendations: {autopilot_recs}\n"
        )

        prompt = ChatPromptTemplate.from_messages([
            ("system", "You are the Analytics & Intelligence Agent for SmartShelfKart.\n"
                       "CRITICAL INSTRUCTIONS:\n"
                       "1. Keep responses short, simple, and creative. Use emojis (📊, ⚠️, 💰, 🚨).\n"
                       "2. Present tabular data, lists, or comparisons as clean, compact markdown tables.\n"
                       "3. Keep each table row aligned on a single line. Avoid long text in columns.\n"
                       "4. Give a single brief summary sentence followed directly by the table."),
            ("user", "Metrics Data:\n{context}\nUser Question: {question}")
        ])

        messages = prompt.format_messages(context=context_str, question=question)
        try:
            response = llm_pro.invoke(messages)
            content = extract_text_content(response.content)
        except Exception as e:
            content = f"Analytics calculation error: {str(e)}"

    stats_payload = {
        "total": metrics["total_products"],
        "low": metrics["low_stock_count"],
        "out": metrics["out_of_stock_count"],
        "total_value": metrics["total_inventory_value"],
        "autopilot_recommendations_count": len(autopilot_recs)
    }
    content += f"\n\n[STATS: {json.dumps(stats_payload)}]"

    state["analytics_data"] = metrics
    state["generation"] = content
    return state

def knowledge_agent_node(state: GraphState) -> GraphState:
    """Handles policy, general guidance, and standard knowledge questions."""
    question = state["question"]
    documents = state["documents"]
    docs_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))

    if api_key == "MOCK_KEY_FOR_INIT":
        content = (
            f"⚡ **Co-Pilot Active**\n\n"
            f"| Capability 🛠️ | Action Supported 🚀 |\n"
            f"| :--- | :--- |\n"
            f"| 📦 Inventory | Update Stock & Audit |\n"
            f"| 🧾 Ordering | Purchase Orders |\n"
            f"| 📊 Analytics | Metrics & Autopilot |\n\n"
            f"⚠️ Set `GOOGLE_API_KEY` in `rag_backend/.env` for full AI capabilities."
        )
    else:
        prompt = ChatPromptTemplate.from_messages([
            ("system", "You are Ask AI, an ultra-smart, friendly inventory co-pilot for SmartShelfKart.\n"
                       "CRITICAL INSTRUCTIONS:\n"
                       "1. Keep responses creative, short, and simple with emojis.\n"
                       "2. Present inventory lists, guides, and policies in clean, compact markdown tables.\n"
                       "3. Keep text aligned on a single line per row where possible."),
            ("user", "Context:\n{context}\nQuestion: {question}")
        ])
        
        messages = prompt.format_messages(context=docs_text, question=question)
        try:
            response = llm_pro.invoke(messages)
            content = extract_text_content(response.content)
        except Exception as e:
            content = f"Connection error: {str(e)}"

    state["generation"] = content
    return state

# Compatibility aliases
retrieve = retrieve_node
generate = action_agent_node
