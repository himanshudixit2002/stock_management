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
from langchain_google_vertexai import ChatVertexAI
from langchain_openai import ChatOpenAI
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage

from state import GraphState
from inventory_db import db_instance
from guardrails import InventoryGuardrails
from predictive_ml import perform_abc_analysis, calculate_stockout_risk_timeline, predict_30day_demand_forecast

class LocalDenseEmbeddings:
    """Fast, deterministic local 384-dim dense embedding model (fallback)."""
    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        return [self._embed(t) for t in texts]

    def embed_query(self, text: str) -> List[float]:
        return self._embed(text)

    def _embed(self, text: str) -> List[float]:
        words = re.sub(r'[^\w\s]', '', text.lower()).split()
        dim = 384
        vec = [0.0] * dim
        import hashlib, math
        for w in words:
            h = int(hashlib.md5(w.encode('utf-8')).hexdigest(), 16)
            idx = h % dim
            val = (h % 100) / 100.0 - 0.5
            vec[idx] += val
        norm = math.sqrt(sum(v*v for v in vec)) or 1.0
        return [v / norm for v in vec]

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

class query_inventory_state(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name to query.")

class predict_demand_velocity(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name to forecast.")

class draft_purchase_order(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name of the item to reorder.")
    reorder_qty: int = Field(description="Quantity to reorder from supplier.")
    supplier_name: Optional[str] = Field(default="Default Supplier", description="Name of supplier/vendor.")

class simulate_financial_impact(BaseModel):
    barcode_or_name: str = Field(description="The barcode or product name for the decision.")
    action_type: str = Field(description="The action being evaluated, e.g. 'reorder', 'clearance'")
    qty: int = Field(description="Quantity involved in the action.")

class detect_anomalies(BaseModel):
    category_or_all: str = Field(default="all", description="Specific category to scan, or 'all'")

# ---------------------------------------------------------
# Keep the old action tools to support fallback rule matcher
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

ACTION_TOOLS = [UpdateStock, CreatePurchaseOrder, TransferStock, AuditInventory, SetReorderAlert]
CONTROLLER_TOOLS = [query_inventory_state, predict_demand_velocity, draft_purchase_order, simulate_financial_impact, detect_anomalies]
EXECUTION_TOOLS = ACTION_TOOLS + CONTROLLER_TOOLS
ANALYTICS_TOOLS = [query_inventory_state, predict_demand_velocity, detect_anomalies]

def get_active_llm(temperature: float = 0.0, bind_tools_list: Optional[List[Any]] = None):
    """
    Factory function returning the active LLM instance.
    Prioritizes Google Gemini AI (via ChatGoogleGenerativeAI or ChatVertexAI).
    """
    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")

    # 1. Google Gemini via ChatGoogleGenerativeAI (if API key available)
    if gemini_key and _is_valid_api_key(gemini_key):
        try:
            llm = ChatGoogleGenerativeAI(
                model="gemini-2.0-flash",
                temperature=temperature,
                google_api_key=gemini_key
            )
            if bind_tools_list:
                return llm.bind_tools(bind_tools_list)
            return llm
        except Exception as e:
            print(f"[LLM Factory] Gemini init error: {e}")

    # 2. Google Gemini via ChatVertexAI (Automatic GCP Service Account IAM on Cloud Run)
    try:
        llm = ChatVertexAI(
            model_name="gemini-2.0-flash",
            project="stockmanagement-27af8",
            location="asia-south1",
            temperature=temperature
        )
        if bind_tools_list:
            return llm.bind_tools(bind_tools_list)
        return llm
    except Exception as e:
        print(f"[LLM Factory] Vertex AI init error: {e}")

    # 3. Tinker AI Fallback
    tinker_key = os.environ.get("TINKER_API_KEY")
    tinker_base_url = os.environ.get("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod/oai/api/v1")
    tinker_model = os.environ.get("TINKER_MODEL", "tinker://default")

    if tinker_key and _is_valid_api_key(tinker_key):
        try:
            llm = ChatOpenAI(
                model=tinker_model,
                temperature=temperature,
                openai_api_key=tinker_key,
                openai_api_base=tinker_base_url
            )
            if bind_tools_list:
                return llm.bind_tools(bind_tools_list)
            return llm
        except Exception as e:
            print(f"[LLM Factory] Tinker AI init error: {e}")

    return None

# ---------------------------------------------------------
# 3. Vectorstore Retriever
# ---------------------------------------------------------

def get_retriever(company_id: str = "default"):
    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if gemini_key and _is_valid_api_key(gemini_key):
        try:
            embeddings = GoogleGenerativeAIEmbeddings(model="models/text-embedding-004", google_api_key=gemini_key)
            vectorstore = Chroma(
                collection_name="stock_inventory",
                embedding_function=embeddings,
                persist_directory="./chroma_db"
            )
            cid = (company_id or "default").strip()
            return vectorstore.as_retriever(search_kwargs={"k": 3, "filter": {"company_id": cid}})
        except Exception as e:
            print(f"Retriever Gemini initialization warning: {e}")

    try:
        embeddings = LocalDenseEmbeddings()
        vectorstore = Chroma(
            collection_name="stock_inventory",
            embedding_function=embeddings,
            persist_directory="./chroma_db"
        )
        cid = (company_id or "default").strip()
        return vectorstore.as_retriever(search_kwargs={"k": 3, "filter": {"company_id": cid}})
    except Exception as e:
        print(f"Retriever local initialization warning: {e}")
    return None




# ---------------------------------------------------------
# 4. Multi-Agent Graph Nodes
# ---------------------------------------------------------

def router_node(state: GraphState) -> GraphState:
    """Fast, low-cost intent router prioritizing zero-token regex matching before any LLM fallback."""
    question = state["question"]
    q = question.lower().strip()
    history = state.get("history") or []
    
    # ── Contextual History Check ──
    if history:
        last_msg = history[-1]
        if last_msg.get("role") in ["assistant", "model"]:
            last_content = last_msg.get("content", "").lower()
            if any(phrase in last_content for phrase in ["quantity", "how many", "which product", "product name", "tell me the product", "please try again with"]):
                state["intent"] = "EXECUTION"
                return state

    # ── Tier 1: Confirmation of Pending Action ──
    confirm_words = ["confirm", "yes", "proceed", "do it", "apply", "ok", "sure", "approve"]
    if any(q == w or q.startswith(w + " ") or q.endswith(" " + w) for w in confirm_words) or q in confirm_words:
        state["intent"] = "EXECUTION"
        return state
        
    # ── Tier 2: Strong Analytics Patterns ──
    strong_analytics = [
        r"\b(analyze|forecast|predict|trend|report|summary|stats|metrics|valuation|worth)\b",
        r"\b(low stock|out of stock|stockout|health audit|inventory audit|audit report|reorder list)\b",
        r"\b(top\s+\d+|highest\s+stock|best\s+seller|deadstock|slow\s+moving)\b",
        r"\b(show\s+(all|inventory|products|catalog|items))\b",
    ]
    if any(re.search(p, q) for p in strong_analytics):
        state["intent"] = "ANALYTICS"
        return state

    # ── Tier 3: Strong Action / Mutation Patterns ──
    strong_action = [
        r"\b(add|deduct|remove|reduce|increase|restock)\b.*\b\d+\b",
        r"\b\d+\b.*\b(add|deduct|remove|reduce|increase|restock)\b",
        r"\b(update stock|create po|purchase order|transfer stock|set threshold|set alert)\b",
        r"\b(reorder|move|audit)\b.*\b(units?|qty|quantity|pieces?)\b",
        r"\b(simulate\s+(finance|financial|margin|cash flow))\b",
    ]
    if any(re.search(p, q) for p in strong_action):
        state["intent"] = "EXECUTION"
        return state

    # ── Tier 4: Default to KNOWLEDGE without extra LLM classification call ──
    state["intent"] = "KNOWLEDGE"
    return state

def retrieve_node(state: GraphState) -> GraphState:
    """Smart context retrieval — only includes products relevant to the query, not the entire catalog."""
    question = state["question"]
    provided_context = state.get("provided_context", "")
    intent = state.get("intent", "KNOWLEDGE")
    company_id = state.get("company_id", "default")

    clean_provided_context = provided_context or ""

    # Legacy catalog injection support (graceful backward compat)
    if provided_context and "[REAL_USER_CATALOG:" in provided_context:
        try:
            match = re.search(r'\[REAL_USER_CATALOG:\s*(\[.*?\])\s*\]', provided_context, re.DOTALL)
            if match:
                catalog_list = json.loads(match.group(1))
                if isinstance(catalog_list, list) and catalog_list:
                    db_instance.replace_user_inventory(catalog_list, company_id=company_id)
                clean_provided_context = provided_context.replace(match.group(0), "").strip()
        except Exception as e:
            print(f"Error loading user catalog into DB: {e}")

    documents = []
    if clean_provided_context:
        documents.append(Document(page_content=clean_provided_context))

    all_products = db_instance.get_all_products(company_id=company_id)
    q_lower = question.lower()

    if intent == "ACTION":
        # For actions: only include products that match the query (max 10)
        matched = []
        for p in all_products:
            p_name = p.get("name", "").lower()
            p_barcode = str(p.get("barcode", "")).strip()
            if p_barcode and p_barcode in question:
                matched.insert(0, p)  # Barcode match = highest priority
            elif any(word in q_lower for word in p_name.split() if len(word) > 2 and word not in {"the", "and", "for", "with", "standard", "premium", "basic", "units", "unit"}):
                matched.append(p)
        # If no match found, include top 10 by lowest stock (most likely targets)
        if not matched:
            matched = sorted(all_products, key=lambda x: int(x.get("stock", 0)))[:10]
        else:
            matched = matched[:10]
        
        if matched:
            db_context_str = "RELEVANT INVENTORY ITEMS:\n" + "\n".join([
                f"- {p['name']} (Barcode: {p['barcode']}) | Stock: {p['stock']} | Min: {p['min_threshold']} | Cost: ${p.get('cost_price', 0):.2f} | Price: ${p.get('selling_price', 0):.2f}"
                for p in matched
            ])
            documents.append(Document(page_content=db_context_str))

    elif intent == "ANALYTICS":
        # For analytics: compact summary + at-risk items only
        total = len(all_products)
        low_stock = [p for p in all_products if 0 < p.get("stock", 0) <= p.get("min_threshold", 10)]
        out_of_stock = [p for p in all_products if p.get("stock", 0) == 0]
        total_val = sum(p.get("stock", 0) * p.get("selling_price", 0) for p in all_products)
        
        summary = (
            f"INVENTORY SUMMARY: {total} products, {len(low_stock)} low stock, {len(out_of_stock)} out of stock, "
            f"Total Value: ${total_val:,.2f}"
        )
        
        # Include at-risk items (max 15)
        risk_items = out_of_stock + low_stock
        if risk_items:
            summary += "\n\nAT-RISK ITEMS:\n" + "\n".join([
                f"- {p['name']} (BC: {p['barcode']}) | Stock: {p['stock']} | Min: {p['min_threshold']}"
                for p in risk_items[:15]
            ])
        
        # Include all products in compact format for analytics (needed for reports)
        if all_products:
            summary += "\n\nFULL INVENTORY:\n" + "\n".join([
                f"- {p['name']} | Stock: {p['stock']} | Min: {p['min_threshold']} | Cat: {p.get('category', 'General')} | Vel: {p.get('sales_velocity', 0)}/day"
                for p in all_products
            ])
        
        documents.append(Document(page_content=summary))

    else:  # KNOWLEDGE
        # For knowledge: use vector search if available, plus compact inventory overview
        if not clean_provided_context:
            try:
                retriever = get_retriever(company_id=company_id)
                if retriever:
                    documents.extend(retriever.invoke(question))
            except Exception as e:
                print(f"Retriever skipped/failed: {e}")
        
        # Add compact inventory overview (not full details)
        if all_products:
            total = len(all_products)
            low = len([p for p in all_products if 0 < p.get("stock", 0) <= p.get("min_threshold", 10)])
            out = len([p for p in all_products if p.get("stock", 0) == 0])
            total_val = sum(p.get("stock", 0) * p.get("selling_price", 0) for p in all_products)
            documents.append(Document(page_content=f"INVENTORY: {total} products, {low} low stock, {out} out of stock, Value: ${total_val:,.2f}"))

    state["documents"] = documents
    return state

def _fallback_rule_matcher(question: str, history: Optional[List[Dict[str, Any]]] = None, company_id: str = "default") -> Optional[Dict[str, Any]]:
    """Fallback action tool matcher when running offline or without an active API key."""
    q = question.lower()
    all_prods = db_instance.get_all_products(company_id=company_id)
    if not all_prods:
        return None

    # Check if the user is confirming a previous action preview
    is_confirm_word = any(w in q for w in ["confirm", "yes", "proceed", "do it", "apply", "ok", "sure", "approve"])

    # If the user question is short or generic like "confirm" / "yes", try extracting pending action from chat history
    pending_action = None
    if is_confirm_word and history:
        for msg in reversed(history):
            role = msg.get("role", "")
            content = msg.get("content", "")
            if role in ["assistant", "model"] and ("Action Confirmation Required" in content or "Requested Change" in content):
                # Extract barcode from previous preview content
                barcode_match = re.search(r'\|\s*\*\*Barcode\*\*\s*\|\s*`([^`]+)`', content) or re.search(r'`([^`]+)`', content)
                qty_match = re.search(r'([+-]?\d+)\s*units', content)
                action_match = re.search(r'Action\*\* \| \*\*(.*?)\*\*', content)
                if barcode_match:
                    bc = barcode_match.group(1).strip()
                    found_p = db_instance.get_product(bc, company_id=company_id)
                    if found_p:
                        qty = 1
                        if qty_match:
                            qty = abs(int(qty_match.group(1)))
                        act_type = action_match.group(1) if action_match else "Add Stock"
                        pending_action = {"product": found_p, "qty": qty, "action_type": act_type}
                        break

    target_product = None
    if pending_action:
        target_product = pending_action["product"]
    else:
        # Step 1: Check for exact Barcode match first
        for p in all_prods:
            p_barcode = str(p.get("barcode", "")).strip()
            if p_barcode and p_barcode in question:
                target_product = p
                break

        # Step 2: Check for exact full product name match in question
        if not target_product:
            for p in all_prods:
                p_name = str(p.get("name", "")).strip().lower()
                if p_name and p_name in q:
                    target_product = p
                    break

        # Step 3: Check for key distinctive words (excluding generic tier words)
        GENERIC_WORDS = {"basic", "standard", "premium", "units", "unit", "add", "deduct", "stock", "barcode", "update", "restock", "item", "items", "confirm", "yes", "proceed"}
        if not target_product:
            best_score = 0
            for p in all_prods:
                p_name = str(p.get("name", "")).strip().lower()
                distinctive_words = [w for w in p_name.split() if w not in GENERIC_WORDS and len(w) > 2]
                score = sum(1 for w in distinctive_words if w in q)
                if score > best_score:
                    best_score = score
                    target_product = p

    if not target_product:
        return None

    # Determine quantity and action type
    if pending_action:
        qty = pending_action["qty"]
        act_type = pending_action["action_type"]
        is_add = "Add" in act_type or "Update" in act_type
        is_deduct = "Deduct" in act_type
        is_po = "Purchase" in act_type or "PO" in act_type
    else:
        target_barcode = str(target_product.get("barcode", "")).strip()
        nums = re.findall(r'\b\d+\b', question)
        # Filter out numbers matching barcode or unusually long numeric IDs (6+ digits)
        qty_nums = [int(n) for n in nums if n != target_barcode and len(n) < 6]
        
        is_add = any(k in q for k in ["add", "increase", "restock"])
        is_deduct = any(k in q for k in ["deduct", "remove", "reduce", "minus"])
        is_po = any(k in q for k in ["reorder", "po", "purchase order"])

        if not qty_nums and not is_confirm_word:
            return {
                "tool": "ActionPreview",
                "preview": f"How many units of **{target_product['name']}** would you like to update? (e.g. 'Add 20 units of {target_product['name']}')",
                "target": target_product
            }
        qty = qty_nums[0] if qty_nums else 1

    if not (is_add or is_deduct or is_po or "update" in q or pending_action):
        return None

    if not is_confirm_word and not pending_action:
        current_stock = int(target_product.get("stock", 0))
        if is_deduct:
            change_str = f"-{qty} units"
            projected_stock = current_stock - qty
            action_type = "Deduct Stock"
        elif is_po:
            change_str = f"+{qty} units (Purchase Order)"
            projected_stock = current_stock + qty
            action_type = "Create Purchase Order"
        else:
            change_str = f"+{qty} units"
            projected_stock = current_stock + qty
            action_type = "Add Stock"

        preview_card = (
            f"Action Confirmation Required\n\n"
            f"Please confirm before updating your live inventory database:\n\n"
            f"| Detail | Information |\n"
            f"| :--- | :--- |\n"
            f"| **Product** | **{target_product['name']}** |\n"
            f"| **Barcode** | `{target_product['barcode']}` |\n"
            f"| **Action** | **{action_type}** |\n"
            f"| **Current Stock** | **{current_stock} units** |\n"
            f"| **Requested Change** | **{change_str}** |\n"
            f"| **Projected Stock** | **{projected_stock} units** |\n\n"
            f"Reply **\"Confirm\"** or **\"Yes, update it\"** to apply this change to your store."
        )
        return {"tool": "ActionPreview", "preview": preview_card, "target": target_product}


    # If confirmed, execute the live DB mutation
    if is_deduct:
        res = db_instance.update_stock(target_product["barcode"], -qty, "Quick Action (Confirmed)", company_id=company_id)
        return {"tool": "UpdateStock", "res": res, "qty": -qty}
    elif is_po:
        res = db_instance.create_purchase_order(target_product["barcode"], qty, "Auto Supplier", company_id=company_id)
        return {"tool": "CreatePurchaseOrder", "res": res, "qty": qty}
    else:
        res = db_instance.update_stock(target_product["barcode"], qty, "Quick Action (Confirmed)", company_id=company_id)
        return {"tool": "UpdateStock", "res": res, "qty": qty}


def _get_business_prompt_context(business_type: str) -> str:
    """Returns industry-specific context for system prompts."""
    prompts = {
        "retail_store": "a retail store owner managing shelf inventory, product restocking, and point-of-sale stock",
        "restaurant": "a restaurant manager tracking ingredients, kitchen supplies, portion-based consumption, and vendor orders",
        "clinic": "a medical clinic administrator managing surgical supplies, medications, consumables, and medical equipment stock",
        "warehouse": "a warehouse operations manager handling bulk storage, zone transfers, incoming shipments, and outbound dispatch",
        "manufacturer": "a manufacturing unit supervisor tracking raw materials, work-in-progress components, and finished goods inventory",
        "pharmacy": "a pharmacy owner managing medication stock, expiry tracking, controlled substance counts, and supplier reorders",
        "ecommerce": "an e-commerce seller managing SKU inventory, fulfillment stock levels, and multi-channel listing quantities",
    }
    return prompts.get(business_type, prompts["retail_store"])


def execution_agent_node(state: GraphState) -> GraphState:
    """Unified execution agent that handles both standard actions and complex controller simulations."""
    question = state["question"]
    documents = state["documents"]
    history = state.get("history") or []
    company_id = state.get("company_id", "default")
    business_type = state.get("business_type", "retail_store")
    
    context_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))
    executed_actions = []
    
    active_llm = get_active_llm(temperature=0, bind_tools_list=EXECUTION_TOOLS)

    if not active_llm:
        state["generation"] = "Execution agent requires an active LLM."
        return state

    biz_context = _get_business_prompt_context(business_type)
    system_prompt = (
        f"You are a unified execution & controller agent for {biz_context}.\n"
        f"You have LIVE access to the database via tools to execute actions or simulate financial impacts.\n"
        f"INVENTORY DATA:\n{context_text}\n\n"
        f"RULES:\n"
        f"1. If the user wants to add/deduct stock, call UpdateStock.\n"
        f"2. If the user wants to simulate finances, call simulate_financial_impact.\n"
        f"3. Do not ask for confirmation unless critical details (like quantity) are missing.\n"
        f"4. After executing tools, summarize the result concisely."
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

    from langchain_core.messages import ToolMessage
    generation = "Action failed."
    if active_llm:
        for _ in range(5):
            try:
                response = active_llm.invoke(messages)
            except Exception as e:
                print(f"[Execution Node] LLM invoke failed: {e}")
                generation = "Action failed."
                break
                
            messages.append(response)
            
            if not hasattr(response, "tool_calls") or not response.tool_calls:
                generation = extract_text_content(response.content)
                break
                
            guardrails = InventoryGuardrails()
            for tool_call in response.tool_calls:
                t_name = tool_call["name"]
                args = tool_call["args"]
                target = args.get("barcode_or_name", "")
                target_product = db_instance.get_product(target, company_id=company_id)
                
                tool_result_str = ""
                if t_name == "UpdateStock":
                    qty_change = args.get("qty_change", 0)
                    if target_product:
                        new_stock = target_product.get("stock", 0) + qty_change
                        validation = guardrails.validate_action("update_stock", {"new_stock": new_stock}, target_product)
                        if not validation.passed:
                            tool_result_str = " Guardrail Blocked: " + " ".join(validation.reasons)
                            executed_actions.append({"tool": "UpdateStock", "result": {"success": False, "error": tool_result_str}})
                            messages.append(ToolMessage(content=tool_result_str, tool_call_id=tool_call["id"]))
                            continue
                    res = db_instance.update_stock(target, qty_change, args.get("reason", "AI Action"), company_id=company_id)
                    executed_actions.append({"tool": "UpdateStock", "result": res})
                    tool_result_str = str(res)
                    
                elif t_name == "CreatePurchaseOrder" or t_name == "draft_purchase_order":
                    reorder_qty = args.get("reorder_qty", 10)
                    if target_product:
                        validation = guardrails.validate_action("create_reorder_po", {"quantity": reorder_qty}, target_product)
                        if not validation.passed:
                            tool_result_str = " Guardrail Blocked: " + " ".join(validation.reasons)
                            executed_actions.append({"tool": t_name, "result": {"success": False, "error": tool_result_str}})
                            messages.append(ToolMessage(content=tool_result_str, tool_call_id=tool_call["id"]))
                            continue
                    res = db_instance.create_purchase_order(target, reorder_qty, args.get("supplier_name", "Default Supplier"), company_id=company_id)
                    executed_actions.append({"tool": t_name, "result": res})
                    tool_result_str = str(res)
                    
                elif t_name == "TransferStock":
                    res = db_instance.transfer_stock(target, args.get("from_location", "Main Store"), args.get("to_location", "Warehouse"), args.get("qty", 1), company_id=company_id)
                    executed_actions.append({"tool": "TransferStock", "result": res})
                    tool_result_str = str(res)
                    
                elif t_name == "AuditInventory":
                    res = db_instance.audit_inventory(target, args.get("actual_stock", 0), args.get("notes", "Physical Audit"), company_id=company_id)
                    executed_actions.append({"tool": "AuditInventory", "result": res})
                    tool_result_str = str(res)
                    
                elif t_name == "SetReorderAlert":
                    res = db_instance.set_min_threshold(target, args.get("new_min_threshold", 10), company_id=company_id)
                    executed_actions.append({"tool": "SetReorderAlert", "result": res})
                    tool_result_str = str(res)
                    
                elif t_name == "query_inventory_state":
                    if target_product:
                        res = {"success": True, "stock": target_product.get("stock"), "min_threshold": target_product.get("min_threshold"), "selling_price": target_product.get("selling_price")}
                    else:
                        res = {"error": "not found"}
                    executed_actions.append({"tool": "query_inventory_state", "result": res})
                    tool_result_str = str(res)

                elif t_name == "predict_demand_velocity":
                    forecast = db_instance.get_predictive_demand_forecast(company_id=company_id)
                    f_item = next((f for f in forecast if f["barcode"] == target), None)
                    res = f_item if f_item else {"error": "not found"}
                    executed_actions.append({"tool": "predict_demand_velocity", "result": res})
                    tool_result_str = str(res)

                elif t_name == "simulate_financial_impact":
                    qty = args.get("qty", 1)
                    if target_product:
                        cost = target_product.get("cost_price", 0) * qty
                        sell = target_product.get("selling_price", 0) * qty
                        margin = sell - cost
                        res = {"cost": cost, "margin": margin}
                    else:
                        res = {"error": "not found"}
                    executed_actions.append({"tool": "simulate_financial_impact", "result": res})
                    tool_result_str = str(res)

                elif t_name == "detect_anomalies":
                    anomalies = db_instance.detect_inventory_anomalies(company_id=company_id)
                    res = {"anomalies": anomalies}
                    executed_actions.append({"tool": "detect_anomalies", "result": res})
                    tool_result_str = str(res)
                else:
                    tool_result_str = f"Unknown tool: {t_name}"
                    
                messages.append(ToolMessage(content=tool_result_str, tool_call_id=tool_call["id"]))

    # ── Fallback Rule Matcher if LLM failed or produced no actions ──
    if not executed_actions or generation == "Action failed.":
        fallback_res = _fallback_rule_matcher(question, history, company_id=company_id)
        if fallback_res:
            tool = fallback_res.get("tool")
            if tool == "ActionPreview":
                generation = fallback_res.get("preview", "")
            elif tool in ["UpdateStock", "CreatePurchaseOrder"]:
                res = fallback_res.get("res", {})
                executed_actions.append({"tool": tool, "result": res})
                generation = res.get("message", "Stock updated successfully.")
            elif tool:
                executed_actions.append({"tool": tool, "result": fallback_res})
                generation = "Action executed successfully."

    state["executed_actions"] = executed_actions
    state["generation"] = generation
    return state

def _is_valid_api_key(key: Optional[str]) -> bool:
    """Validates if a real API key (Google Gemini or Tinker AI) is present."""
    if not key or key in ["MOCK_KEY_FOR_INIT", "your_gemini_api_key_here", "YOUR_GEMINI_API_KEY", "your_tinker_api_key_here"]:
        return False
    key_str = str(key).strip()
    if key_str.startswith("AIza") or key_str.startswith("tml-") or len(key_str) >= 20:
        return True
    return False




def _generate_instant_table_response(question: str, metrics: Dict[str, Any], autopilot_recs: List[Dict[str, Any]], company_id: str = "default") -> Optional[str]:
    """Generates instant (< 1ms) markdown table responses for standard audit, order log, reorder, and metric queries."""
    q = question.lower()

    # 0. Single Top Priority Item to Buy / Order
    if any(k in q for k in ["exact one product", "one product", "exact product", "single product", "single item", "what to buy now", "should buy now", "top product to buy", "which product to buy", "exact item", "should buy", "what exact product"]):
        recs = autopilot_recs or db_instance.run_autopilot_scan(company_id=company_id)
        all_prods = db_instance.get_all_products(company_id=company_id)
        
        target_item = None
        if recs:
            target_item = recs[0]
            name = target_item.get("product_name") or target_item.get("name")
            barcode = target_item.get("barcode")
            stock = target_item.get("current_stock", target_item.get("stock", 0))
            suggested_qty = target_item.get("suggested_reorder_qty", 10)
            urgency = str(target_item.get("urgency", "HIGH")).upper()
        elif all_prods:
            sorted_prods = sorted(all_prods, key=lambda x: int(x.get("stock", 0)))
            top_p = sorted_prods[0]
            name = top_p.get("name")
            barcode = top_p.get("barcode")
            stock = int(top_p.get("stock", 0))
            threshold = int(top_p.get("min_threshold", 10))
            suggested_qty = max(10, threshold * 2 - stock)
            urgency = "CRITICAL (Stockout)" if stock == 0 else "HIGH (Low Stock)"
        else:
            return "No inventory items found in your store to analyze."

        return (
            f"### Priority Purchase Recommendation\n\n"
            f"Based on your real-time inventory analysis, the **#1 exact product** you should buy right now is:\n\n"
            f"| Detail | Value |\n"
            f"| :--- | :--- |\n"
            f"| **Product** | **{name}** |\n"
            f"| **Barcode** | `{barcode}` |\n"
            f"| **Current Stock** | **{stock} units** |\n"
            f"| **Suggested Reorder** | **+{suggested_qty} units** |\n"
            f"| **Urgency Level** | **{urgency}** |\n\n"
            f"Would you like me to create a purchase order for **{name}**? Reply **\"Add {suggested_qty} units of {name}\"** to proceed."
        )

    # 1. Business Growth / Revenue Strategy tailored to real store inventory
    if any(k in q for k in ["grow my business", "grow business", "growth strategy", "boost sales", "increase revenue", "grow revenue", "help me grow", "growth plan"]):
        low_count = metrics.get("low_stock_count", 0)
        out_count = metrics.get("out_of_stock_count", 0)
        total_prods = metrics.get("total_products", 0)
        total_val = metrics.get("total_inventory_value", 0.0)
        
        top_risk_name = "your low stock SKUs"
        if autopilot_recs:
            top_risk_name = f"'{autopilot_recs[0].get('product_name')}'"
        elif metrics.get("low_stock_items"):
            top_risk_name = f"'{metrics['low_stock_items'][0].get('name')}'"

        return (
            f"Here are 5 high-impact growth strategies tailored to your store (**{total_prods} SKUs**, **${total_val:,.2f}** inventory valuation):\n\n"
            f"| Strategy | Actionable Execution for Your Store | Expected Impact |\n"
            f"| :--- | :--- | :--- |\n"
            f"| **1. Prevent Stockout Losses** | Restock your **{low_count + out_count} at-risk items** (like {top_risk_name}) before sales drop | **+8% Revenue** |\n"
            f"| **2. Strategic Product Bundling** | Pair slow-moving stock with top-selling essentials at a 5% discount | **+5% Basket Value** |\n"
            f"| **3. Optimize Supplier Lead Times** | Negotiate shorter vendor fulfillment windows for fast movers | **+4% Cash Flow** |\n"
            f"| **4. Re-order Reminders** | Send automated replenishment alerts for high-turnover consumables | **+3% Repeat Purchase** |\n"
            f"| **5. Liquidate Dead Stock** | Clearance-sale slow-moving items with zero sales in 60+ days | **Instant Cash Recovery** |\n\n"
            f"Would you like me to analyze your top-selling products or generate purchase orders for your {low_count + out_count} low-stock items?"
        )

    # 2. Reorder / What to order next queries
    if any(k in q for k in ["order next", "what to order", "reorder next", "what to buy", "reorder suggestion", "autopilot"]):
        recs = autopilot_recs or db_instance.run_autopilot_scan(company_id=company_id)
        if not recs:
            return "Great news! All products are well-stocked right now. No immediate reorders needed."
        
        rows = []
        for r in recs:
            urg = r.get("urgency", "MEDIUM").title()
            rows.append(f"| **{r['product_name']}** | `{r['barcode']}` | **{r['current_stock']}** | **+{r['suggested_reorder_qty']} units** | {urg} |")
            
        table = (
            "Based on current sales velocity and safety stock, here is what you should **order next**:\n\n"
            "| Product | Barcode | Current Stock | Suggested Reorder | Urgency |\n"
            "| :--- | :--- | :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )
        return table
    
    # 3. Order Log / Ledger / Purchase Order History
    if any(k in q for k in ["order log", "log table", "ledger", "transaction history", "po log", "order history", "action ledger", "audit log", "recent actions"]):
        ledger = db_instance._get_company(company_id)["action_ledger"]
        if not ledger:
            return "Here is your order log: No transactions recorded yet."
        
        recent = list(reversed(ledger[-10:])) # Show latest 10 actions
        rows = []
        for item in recent:
            ts = item.get("timestamp", "").replace("T", " ")[:16]
            action = item.get("action", "Action").replace("_", " ").title()
            prod = item.get("product_name") or item.get("barcode") or "Item"
            
            if action == "Update Stock":
                details = f"Stock: {item.get('old_stock')} -> **{item.get('new_stock')}** ({item.get('qty_change', 0):+d})"
            elif action == "Create Purchase Order":
                details = f"PO #{item.get('po_id')} | Qty: **{item.get('reorder_qty')}** | Cost: **${item.get('total_cost', 0):,.2f}**"
            elif action == "Transfer Stock":
                details = f"Qty: **{item.get('qty')}** to **{item.get('to_location')}**"
            elif action == "Audit Inventory":
                details = f"Adjusted to **{item.get('actual_stock')}** (Diff: {item.get('discrepancy', 0):+d})"
            elif action == "Set Min Threshold":
                details = f"New threshold: **{item.get('new_threshold')}** (was {item.get('old_threshold')})"
            else:
                details = str(item.get("details", "Logged"))
                
            rows.append(f"| {ts} | **{action}** | {prod} | {details} |")
            
        table = (
            "Here is your recent **Order & Action Log**:\n\n"
            "| Timestamp | Action | Product | Details |\n"
            "| :--- | :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )
        return table

    # 4. Inventory Health Audit / Stock Audit Report
    if any(k in q for k in ["inventory audit", "stock audit", "health audit", "audit report", "audit table"]):
        all_prods = db_instance.get_all_products(company_id=company_id)
        if not all_prods:
            return "No products found in inventory to audit."

        
        # Deduplicate by barcode
        seen_barcodes = set()
        dedup_prods = []
        for p in all_prods:
            bc = str(p.get("barcode", "")).strip()
            if bc and bc not in seen_barcodes:
                seen_barcodes.add(bc)
                dedup_prods.append(p)

        def risk_score(p):
            st = p.get("stock", 0)
            th = p.get("min_threshold", 10)
            if st == 0:
                return 0
            if st <= th:
                return 1
            return 2

        sorted_prods = sorted(dedup_prods, key=risk_score)
        
        total_count = len(sorted_prods)
        out_of_stock = [p for p in sorted_prods if p.get("stock", 0) == 0]
        low_stock = [p for p in sorted_prods if 0 < p.get("stock", 0) <= p.get("min_threshold", 10)]
        healthy_count = total_count - len(out_of_stock) - len(low_stock)
        total_val = sum(p.get("stock", 0) * p.get("selling_price", 0.0) for p in sorted_prods)

        # Pick risk items to display in table (at-risk items first, max 20 rows to prevent text wall)
        display_items = (out_of_stock + low_stock)
        if not display_items:
            display_items = sorted_prods[:15]
        elif len(display_items) < 15:
            remaining = [p for p in sorted_prods if p not in display_items]
            display_items.extend(remaining[:15 - len(display_items)])

        rows = []
        for p in display_items:
            stock = p.get("stock", 0)
            threshold = p.get("min_threshold", 10)
            if stock == 0:
                status = "Out of Stock"
                risk = "High"
            elif stock <= threshold:
                status = "Low Stock"
                risk = "Medium"
            else:
                status = "Healthy"
                risk = "Safe"
            rows.append(f"| **{p['name']}** | `{p['barcode']}` | **{stock}** | {threshold} | {status} | {risk} |")

        table = (
            f"Here is your **Executive Inventory Health Audit**:\n\n"
            f"- **Total Products Audited**: **{total_count} items**\n"
            f"- **Healthy Stock**: **{healthy_count} items**\n"
            f"- **Low Stock Warnings**: **{len(low_stock)} items**\n"
            f"- **Out of Stock**: **{len(out_of_stock)} items**\n"
            f"- **Total Portfolio Value**: **${total_val:,.2f}**\n\n"
            f"### Priority Action & Risk Items ({len(display_items)} Shown)\n\n"
            "| Product | Barcode | Stock | Threshold | Status | Risk Level |\n"
            "| :--- | :--- | :--- | :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )
        return table

    # 5. Low Stock / Out of Stock List / Reorder Alert
    if any(k in q for k in ["low stock", "out of stock", "reorder list", "stock alert", "low stock list", "stockout"]):
        low_items = metrics.get("low_stock_items", [])
        out_items = metrics.get("out_of_stock_items", [])
        combined = out_items + low_items
        if not combined:
            return "Great news! All products are currently above their safety thresholds. No low stock items right now."
        
        rows = []
        for p in combined:
            stock = p.get("stock", 0)
            threshold = p.get("min_threshold", 10)
            status = "Out of Stock" if stock == 0 else "Low Stock"
            rows.append(f"| **{p['name']}** | `{p['barcode']}` | **{stock}** | {threshold} | {status} |")
            
        table = (
            "Here is your current **Low Stock & Risk Items** list:\n\n"
            "| Product | Barcode | Current Stock | Safety Threshold | Alert Level |\n"
            "| :--- | :--- | :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )
        return table

    # 6. Summary / Metrics / Valuation Snapshot
    if any(k in q for k in ["summary", "snapshot", "stats", "metrics", "valuation"]):
        table = (
            f"Here is your real-time **Inventory Summary & Valuation**:\n\n"
            f"| Metric | Value |\n"
            f"| :--- | :--- |\n"
            f"| Registered Products | **{metrics['total_products']}** items |\n"
            f"| Low Stock Warnings | **{metrics['low_stock_count']}** items |\n"
            f"| Out of Stock Items | **{metrics['out_of_stock_count']}** items |\n"
            f"| Total Selling Valuation | **${metrics['total_inventory_value']:,.2f}** |\n"
            f"| Total Cost Basis Valuation | **${metrics['total_cost_value']:,.2f}** |\n"
            f"| Autopilot Reorder Suggestions | **{len(autopilot_recs)}** items |"
        )
        return table

    # 7. Show All Products / Product List / Inventory List
    if any(k in q for k in ["show all", "all products", "product list", "inventory list", "full list", "list everything", "show inventory", "all items"]):
        all_prods = db_instance.get_all_products(company_id=company_id)
        if not all_prods:
            return "No products in inventory."
        
        sorted_prods = sorted(all_prods, key=lambda x: x.get("name", ""))
        display = sorted_prods[:25]  # Cap at 25 to avoid token explosion
        
        rows = []
        for p in display:
            rows.append(f"| **{p['name']}** | `{p['barcode']}` | **{p['stock']}** | {p.get('min_threshold', 10)} | {p.get('category', 'General')} | ${p.get('selling_price', 0):.2f} |")
        
        table = (
            f"**{len(all_prods)} products** in your inventory" + (f" (showing top 25)" if len(all_prods) > 25 else "") + ":\n\n"
            "| Product | Barcode | Stock | Min | Category | Price |\n"
            "| :--- | :--- | :--- | :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )
        return table

    # 8. Total Inventory Value / How much is my stock worth
    if any(k in q for k in ["total value", "inventory value", "how much worth", "stock worth", "portfolio value", "total cost"]):
        total_sell = metrics.get("total_inventory_value", 0)
        total_cost = metrics.get("total_cost_value", 0)
        margin = total_sell - total_cost if total_cost > 0 else 0
        return (
            f"**Inventory Valuation:**\n\n"
            f"| Metric | Amount |\n"
            f"| :--- | :--- |\n"
            f"| Selling Value | **${total_sell:,.2f}** |\n"
            f"| Cost Basis | **${total_cost:,.2f}** |\n"
            f"| Unrealized Margin | **${margin:,.2f}** |\n"
            f"| Total Products | **{metrics['total_products']}** |"
        )

    # 9. Top N items by stock level
    if re.search(r'\b(top|highest|most)\b.*\b(stock|stocked|inventory|items|products)\b', q):
        all_prods = db_instance.get_all_products(company_id=company_id)
        if not all_prods:
            return "No products found."
        
        nums = re.findall(r'\b(\d+)\b', q)
        n = int(nums[0]) if nums else 5
        n = min(n, 20)
        
        sorted_prods = sorted(all_prods, key=lambda x: int(x.get("stock", 0)), reverse=True)[:n]
        rows = [f"| **{p['name']}** | **{p['stock']}** | {p.get('category', 'General')} |" for p in sorted_prods]
        
        return (
            f"**Top {n} products by stock level:**\n\n"
            "| Product | Stock | Category |\n"
            "| :--- | :--- | :--- |\n" +
            "\n".join(rows)
        )

    # 10. Single product stock lookup: "what is the stock of X" / "how much X do I have"
    stock_match = re.search(r'(?:stock of|how (?:much|many)|quantity of|check stock)\s+(.+?)(?:\?|$)', q)
    if stock_match:
        product_name = stock_match.group(1).strip().rstrip('?. ')
        all_prods = db_instance.get_all_products(company_id=company_id)
        found = None
        for p in all_prods:
            p_name = p.get("name", "").lower()
            p_barcode = str(p.get("barcode", "")).strip()
            if product_name == p_name or product_name == p_barcode:
                found = p
                break
            elif product_name in p_name or any(w in p_name for w in product_name.split() if len(w) > 2):
                found = p
                break
        
        if found:
            stock = found.get("stock", 0)
            threshold = found.get("min_threshold", 10)
            status = "Out of Stock" if stock == 0 else ("Low" if stock <= threshold else "OK")
            return (
                f"**{found['name']}** (`{found['barcode']}`):\n\n"
                f"| Detail | Value |\n"
                f"| :--- | :--- |\n"
                f"| Stock | **{stock} units** |\n"
                f"| Threshold | {threshold} |\n"
                f"| Status | **{status}** |\n"
                f"| Price | ${found.get('selling_price', 0):.2f} |"
            )

    return None


def analytics_agent_node(state: GraphState) -> GraphState:
    """Data-driven analytics with LLM formatting and tool calling. Concise tables, not essays."""
    question = state["question"]
    company_id = state.get("company_id", "default")
    business_type = state.get("business_type", "retail_store")
    history = state.get("history") or []
    metrics = db_instance.get_analytics_summary(company_id=company_id)
    autopilot_recs = db_instance.run_autopilot_scan(company_id=company_id)
    executed_actions = []

    # Check for instant zero-cost table response first
    instant = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)
    if instant:
        stats_payload = {
            "total": metrics["total_products"],
            "low": metrics["low_stock_count"],
            "out": metrics["out_of_stock_count"],
            "total_value": metrics["total_inventory_value"],
            "autopilot_recommendations_count": len(autopilot_recs)
        }
        state["analytics_data"] = metrics
        state["generation"] = instant + f"\n\n[STATS: {json.dumps(stats_payload)}]"
        return state

    active_llm = get_active_llm(temperature=0.1, bind_tools_list=ANALYTICS_TOOLS)
    if not active_llm:
        content = _generate_instant_table_response("summary", metrics, autopilot_recs, company_id=company_id) or "No analytics LLM available."
        stats_payload = {
            "total": metrics["total_products"],
            "low": metrics["low_stock_count"],
            "out": metrics["out_of_stock_count"],
            "total_value": metrics["total_inventory_value"],
            "autopilot_recommendations_count": len(autopilot_recs)
        }
        state["analytics_data"] = metrics
        state["generation"] = content + f"\n\n[STATS: {json.dumps(stats_payload)}]"
        return state

    biz_context = _get_business_prompt_context(business_type)
    system_prompt = (
        f"You are a data analyst for {biz_context}.\n"
        f"METRICS:\n"
        f"- Products: {metrics['total_products']} | Low: {metrics['low_stock_count']} | Out: {metrics['out_of_stock_count']}\n"
        f"- Selling Value: ${metrics['total_inventory_value']:,.2f} | Cost Value: ${metrics['total_cost_value']:,.2f}\n"
        f"RULES:\n"
        f"1. You have tools to query the database. USE THEM if the user asks for specific forecasts, anomalies, or product states.\n"
        f"2. Answer the user's question using ONLY the provided data. No hallucination.\n"
        f"3. Use markdown tables for any list > 2 items. Keep tables clean.\n"
        f"4. Maximum 3 short paragraphs. Lead with the key number.\n"
        f"5. No fluff. No 'As an AI'. No generic advice. Data only."
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

    from langchain_core.messages import ToolMessage
    generation = "Analytics failed."
    for _ in range(5):
        try:
            response = active_llm.invoke(messages)
        except Exception as e:
            print(f"[Analytics Node] LLM invoke failed: {e}")
            generation = _generate_instant_table_response("summary", metrics, autopilot_recs, company_id=company_id) or "Analytics unavailable."
            break
            
        messages.append(response)
        
        if not hasattr(response, "tool_calls") or not response.tool_calls:
            generation = extract_text_content(response.content)
            break
            
        for tool_call in response.tool_calls:
            t_name = tool_call["name"]
            args = tool_call["args"]
            target = args.get("barcode_or_name", "")
            target_product = db_instance.get_product(target, company_id=company_id)
            
            tool_result_str = ""
            if t_name == "query_inventory_state":
                if target_product:
                    res = {"success": True, "stock": target_product.get("stock"), "min_threshold": target_product.get("min_threshold"), "selling_price": target_product.get("selling_price")}
                else:
                    res = {"error": "not found"}
                executed_actions.append({"tool": "query_inventory_state", "result": res})
                tool_result_str = str(res)

            elif t_name == "predict_demand_velocity":
                forecast = db_instance.get_predictive_demand_forecast(company_id=company_id)
                f_item = next((f for f in forecast if f["barcode"] == target), None)
                res = f_item if f_item else {"error": "not found"}
                executed_actions.append({"tool": "predict_demand_velocity", "result": res})
                tool_result_str = str(res)

            elif t_name == "detect_anomalies":
                anomalies = db_instance.detect_inventory_anomalies(company_id=company_id)
                res = {"anomalies": anomalies}
                executed_actions.append({"tool": "detect_anomalies", "result": res})
                tool_result_str = str(res)
            else:
                tool_result_str = f"Unknown tool: {t_name}"
                
            messages.append(ToolMessage(content=tool_result_str, tool_call_id=tool_call["id"]))

    stats_payload = {
        "total": metrics["total_products"],
        "low": metrics["low_stock_count"],
        "out": metrics["out_of_stock_count"],
        "total_value": metrics["total_inventory_value"],
        "autopilot_recommendations_count": len(autopilot_recs)
    }
    generation += f"\n\n[STATS: {json.dumps(stats_payload)}]"

    state["analytics_data"] = metrics
    state["generation"] = generation
    state["executed_actions"] = executed_actions
    return state

def knowledge_agent_node(state: GraphState) -> GraphState:
    """Handles questions about inventory practices, business advice, and general guidance."""
    question = state["question"]
    documents = state["documents"]
    company_id = state.get("company_id", "default")
    business_type = state.get("business_type", "retail_store")
    docs_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))

    metrics = db_instance.get_analytics_summary(company_id=company_id)
    autopilot_recs = db_instance.run_autopilot_scan(company_id=company_id)

    # Check for instant table response match first
    instant_table = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)
    if instant_table:
        state["generation"] = instant_table
        return state

    q = question.lower()

    # Friendly greeting / intro
    if any(k in q for k in ["tell me about yourself", "who are you", "what can you do", "what are you", "what is ask ai", "hello", "hi", "hey"]):
        biz = business_type.replace("_", " ").title()
        content = (
            f"I'm **Ask AI** — your {biz} inventory assistant.\n\n"
            f"| What I Do | Example Command |\n"
            f"| :--- | :--- |\n"
            f"| **Update Stock** | *Add 50 units of Cannula* |\n"
            f"| **Create PO** | *Reorder 100 units of Bandages* |\n"
            f"| **Stock Audit** | *Show health audit* |\n"
            f"| **Analytics** | *What should I order next?* |\n"
            f"| **Forecast** | *Forecast demand for 30 days* |\n\n"
            f"Just tell me what you need."
        )
    else:
        llm_knowledge = get_active_llm(temperature=0.2)
        if llm_knowledge:
            company_data = db_instance._get_company(company_id=company_id)
            action_ledger = company_data.get("action_ledger", [])
            recent_ledger = list(reversed(action_ledger[-10:]))
            
            biz_context = _get_business_prompt_context(business_type)
            context_str = docs_text + "\n\n" + f"RECENT ACTIONS:\n{json.dumps(recent_ledger, indent=1)}"

            prompt = ChatPromptTemplate.from_messages([
                ("system", f"You are a direct, practical inventory advisor for {biz_context}.\n"
                           f"RULES:\n"
                           f"1. Answer the question directly. No preamble.\n"
                           f"2. Use the user's actual inventory data and transaction history when relevant.\n"
                           f"3. Give actionable advice, not theory. Specific products and numbers.\n"
                           f"4. Maximum 4 bullet points or a short table. No essays.\n"
                           f"5. No 'As an AI', no disclaimers, no 'I recommend'. Just answer."),
                ("user", "Context:\n{context}\n\nQuestion: {question}")
            ])
            
            messages = prompt.format_messages(context=context_str, question=question)
            try:
                response = llm_knowledge.invoke(messages)
                content = extract_text_content(response.content)
            except Exception as e:
                print(f"[Knowledge Node] LLM invoke failed: {e}")
                content = (
                    f"**{metrics['total_products']}** products | "
                    f"**{metrics['low_stock_count']}** low | "
                    f"**{metrics['out_of_stock_count']}** out | "
                    f"Value: **${metrics['total_inventory_value']:,.2f}**\n\n"
                    f"What would you like to know?"
                )
        else:
            content = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)
            if not content:
                content = (
                    f"**{metrics['total_products']}** products | "
                    f"**{metrics['low_stock_count']}** low | "
                    f"**{metrics['out_of_stock_count']}** out | "
                    f"Value: **${metrics['total_inventory_value']:,.2f}**\n\n"
                    f"Ask me anything about your inventory."
                )

    state["generation"] = content
    return state


# Compatibility aliases
retrieve = retrieve_node
generate = execution_agent_node
