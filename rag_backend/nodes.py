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
                model="gemini-1.5-flash",
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
            model_name="gemini-1.5-flash",
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
            embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-2", google_api_key=gemini_key)
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
    """Classifies user intent into ACTION, ANALYTICS, or KNOWLEDGE using fast regex heuristics for instant responses."""
    question = state["question"].lower()
    
    action_keywords = [
        r"\bupdate\b", r"\badd\b", r"\bdeduct\b", r"\bremove\b", r"\breorder\b", 
        r"\bpo\b", r"\bpurchase order\b", r"\btransfer\b", r"\bmove\b", r"\baudit\b", 
        r"\bset threshold\b", r"\balert\b", r"\bconfirm\b", r"\byes\b", r"\bproceed\b", 
        r"\bapprove\b", r"\bdo it\b", r"\bapply\b"
    ]
    analytics_keywords = [
        r"\banalyze\b", r"\bforecast\b", r"\btrend\b", r"\bpredict\b", r"\bgrowth\b", 
        r"\breport\b", r"\bsummary\b", r"\bstats\b", r"\bmetrics\b", r"\btop\b", 
        r"\blow stock\b", r"\bout of stock\b", r"\bvaluation\b", r"\border log\b", 
        r"\blog\b", r"\bledger\b", r"\bhistory\b", r"\btransactions\b", r"\btable\b", 
        r"\brisk\b", r"\babc\b", r"\bcategorize\b"
    ]
    
    is_health_audit = ("health audit" in question or "inventory audit" in question or "audit report" in question or "audit summary" in question or "order log" in question or "log table" in question) and not any(re.search(kw, question) for kw in [r"\bconfirm\b", r"\byes\b", r"\bproceed\b", r"\bapprove\b"])
    
    is_action = any(re.search(kw, question) for kw in action_keywords) and not is_health_audit
    is_analytics = any(re.search(kw, question) for kw in analytics_keywords) or is_health_audit
    
    if is_action:
        intent = "ACTION"
    elif is_analytics:
        intent = "ANALYTICS"
    else:
        intent = "KNOWLEDGE"
        
    state["intent"] = intent
    return state

def retrieve_node(state: GraphState) -> GraphState:
    """Retrieves vector context AND pulls live database records with zero redundant network/embedding calls."""
    question = state["question"]
    provided_context = state.get("provided_context", "")
    intent = state.get("intent", "KNOWLEDGE")
    company_id = state.get("company_id", "default")

    clean_provided_context = provided_context or ""

    if provided_context and "[REAL_USER_CATALOG:" in provided_context:
        try:
            match = re.search(r'\[REAL_USER_CATALOG:\s*(\[.*?\])\s*\]', provided_context, re.DOTALL)
            if match:
                catalog_list = json.loads(match.group(1))
                if isinstance(catalog_list, list) and catalog_list:
                    db_instance.replace_user_inventory(catalog_list, company_id=company_id)
                # Strip out raw JSON string from provided context so it doesn't double LLM prompt token size
                clean_provided_context = provided_context.replace(match.group(0), "").strip()
        except Exception as e:
            print(f"Error loading user catalog into DB: {e}")

    documents = []
    if clean_provided_context:
        documents.append(Document(page_content=clean_provided_context))

    # Fast path: Only call vector embedding search for KNOWLEDGE intent when no clean context exists
    if intent == "KNOWLEDGE" and not clean_provided_context:
        try:
            retriever = get_retriever(company_id=company_id)
            if retriever:
                documents.extend(retriever.invoke(question))
        except Exception as e:
            print(f"Retriever skipped/failed: {e}")


    # Compact live DB record list (avoids token bloat)
    all_products = db_instance.get_all_products(company_id=company_id)
    if all_products:
        db_context_str = "LIVE USER INVENTORY DATABASE:\n" + "\n".join([
            f"- {p['name']} (BC: {p['barcode']}) | Stock: {p['stock']} | Min: {p['min_threshold']} | Cat: {p.get('category', 'General')}"
            for p in all_products
        ])
        documents.append(Document(page_content=db_context_str))

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


def action_agent_node(state: GraphState) -> GraphState:
    """Executes tools against live Inventory DB and logs ledger mutations."""
    question = state["question"]
    documents = state["documents"]
    history = state.get("history") or []
    company_id = state.get("company_id", "default")
    
    context_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))
    executed_actions = []
    
    active_llm = get_active_llm(temperature=0, bind_tools_list=ACTION_TOOLS)

    # Check if active LLM is available
    if not active_llm:
        # Rule-based fallback tool execution (instant < 1ms)
        fallback_res = _fallback_rule_matcher(question, history, company_id=company_id)
        if fallback_res:
            tool_name = fallback_res["tool"]
            if tool_name == "ActionPreview":
                generation = fallback_res["preview"]
            else:
                res = fallback_res["res"]
                executed_actions.append({"tool": tool_name, "result": res})
                if res.get("success"):
                    p = res.get("product", {})
                    if tool_name == "UpdateStock":
                        generation = f"Done! Updated **{p.get('name')}** stock from {res['old_stock']} to **{res['new_stock']} units**."
                    elif tool_name == "CreatePurchaseOrder":
                        generation = f"All set! Created **PO {res['po_id']}** for **{res['reorder_qty']} units** of **{p.get('name')}** (Est. Cost: **${res.get('total_cost', 0):,.2f}**)."
                    else:
                        generation = f"Done! Action processed successfully for **{p.get('name')}**."
                else:
                    generation = f"Couldn't complete action: {res.get('error')}"
        else:
            generation = "I'm ready to update stock! Tell me the product name or barcode and quantity (e.g. 'Add 10 units of Cannula Standard')."
            
        state["executed_actions"] = executed_actions
        state["generation"] = generation
        return state

    system_prompt = (
        "You are an expert, autonomous stock management assistant helping a store owner.\n"
        "You have live access to the user's inventory database context and action tools:\n"
        "- UpdateStock(barcode_or_name, qty_change, reason)\n"
        "- CreatePurchaseOrder(barcode_or_name, reorder_qty, supplier_name)\n"
        "- TransferStock(barcode_or_name, from_location, to_location, qty)\n"
        "- AuditInventory(barcode_or_name, actual_stock, notes)\n"
        "- SetReorderAlert(barcode_or_name, new_min_threshold)\n\n"
        "DATABASE Context:\n" + context_text + "\n\n"
        "CRITICAL INSTRUCTIONS:\n"
        "1. Inspect the user request and recent chat history carefully.\n"
        "2. If the user is requesting a stock update/addition/deduction/reorder for the first time without confirmation:\n"
        "   Do NOT call the tool immediately. Present a clean 'Action Confirmation Required' card detailing Product, Barcode, Action, Current Stock, Requested Change, and Projected Stock, and ask the user to confirm.\n"
        "3. If the user confirms (e.g. 'confirm', 'yes', 'proceed', 'do it') or explicitly requests immediate execution:\n"
        "   Invoke the appropriate function tool (UpdateStock, CreatePurchaseOrder, etc.) with the exact product barcode/name and quantity.\n"
        "4. Speak naturally in clean, human markdown text without bloated emojis or generic disclaimers."
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
        response = active_llm.invoke(messages)
    except Exception as e:
        print(f"[Action Node] LLM invoke failed, using fallback: {e}")

        # Fallback to rule matcher on API model error
        fallback_res = _fallback_rule_matcher(question, history, company_id=company_id)
        if fallback_res:
            tool_name = fallback_res["tool"]
            if tool_name == "ActionPreview":
                generation = fallback_res["preview"]
            else:
                res = fallback_res["res"]
                executed_actions.append({"tool": tool_name, "result": res})
                if res.get("success"):
                    p = res.get("product", {})
                    generation = f"Done! Updated **{p.get('name')}** stock from {res['old_stock']} to **{res['new_stock']} units**."
                else:
                    generation = f"Couldn't complete action: {res.get('error')}"
        else:
            generation = "Action execution fallback completed."
        state["executed_actions"] = executed_actions
        state["generation"] = generation
        return state

    if hasattr(response, "tool_calls") and response.tool_calls:
        guardrails = InventoryGuardrails()
        for tool_call in response.tool_calls:
            t_name = tool_call["name"]
            args = tool_call["args"]
            target = args.get("barcode_or_name", "")
            
            target_product = db_instance.get_product(target, company_id=company_id)

            if t_name == "UpdateStock":
                qty_change = args.get("qty_change", 0)
                if target_product:
                    new_stock = target_product.get("stock", 0) + qty_change
                    validation = guardrails.validate_action("update_stock", {"new_stock": new_stock}, target_product)
                    if not validation.passed:
                        executed_actions.append({"tool": "UpdateStock", "result": {"success": False, "error": " Guardrail Blocked: " + " ".join(validation.reasons)}})
                        generation = f"Action blocked by safety guardrails: {validation.reasons[0]}"
                        continue

                res = db_instance.update_stock(target, qty_change, args.get("reason", "API Action"), company_id=company_id)
                executed_actions.append({"tool": "UpdateStock", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"Done! Updated **{p['name']}** stock from {res['old_stock']} to **{res['new_stock']} units**."
                else:
                    generation = f"Couldn't update stock for {target}: {res.get('error')}"

            elif t_name == "CreatePurchaseOrder":
                reorder_qty = args.get("reorder_qty", 10)
                if target_product:
                    validation = guardrails.validate_action("create_reorder_po", {"quantity": reorder_qty}, target_product)
                    if not validation.passed:
                        executed_actions.append({"tool": "CreatePurchaseOrder", "result": {"success": False, "error": " Guardrail Blocked: " + " ".join(validation.reasons)}})
                        generation = f"Action blocked by safety guardrails: {validation.reasons[0]}"
                        continue
                        
                res = db_instance.create_purchase_order(target, reorder_qty, args.get("supplier_name", "Default Supplier"), company_id=company_id)
                executed_actions.append({"tool": "CreatePurchaseOrder", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"All set! Created **PO {res['po_id']}** for **{res['reorder_qty']} units** of **{p['name']}** from **{res['supplier']}** (Est. Cost: **${res['total_cost']:.2f}**)."
                else:
                    generation = f"Couldn't create purchase order: {res.get('error')}"

            elif t_name == "TransferStock":
                res = db_instance.transfer_stock(target, args.get("from_location", "Main Store"), args.get("to_location", "Warehouse"), args.get("qty", 1), company_id=company_id)
                executed_actions.append({"tool": "TransferStock", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"Moved **{res['qty']} units** of **{p['name']}** to **{res['to_location']}**."
                else:
                    generation = f"Couldn't transfer stock: {res.get('error')}"

            elif t_name == "AuditInventory":
                res = db_instance.audit_inventory(target, args.get("actual_stock", 0), args.get("notes", "Physical Audit"), company_id=company_id)
                executed_actions.append({"tool": "AuditInventory", "result": res})
                if res.get("success"):
                    p = res["product"]
                    disc = res['discrepancy']
                    disc_str = f"+{disc}" if disc > 0 else f"{disc}"
                    generation = f"Audit complete! Adjusted **{p['name']}** from {res['old_stock']} to **{res['actual_stock']} units** (Diff: **{disc_str}**)."
                else:
                    generation = f"Audit logging failed: {res.get('error')}"

            elif t_name == "SetReorderAlert":
                res = db_instance.set_min_threshold(target, args.get("new_min_threshold", 10), company_id=company_id)
                executed_actions.append({"tool": "SetReorderAlert", "result": res})
                if res.get("success"):
                    p = res["product"]
                    generation = f"Updated safety threshold for **{p['name']}** to **{res['new_threshold']} units** (was {res['old_threshold']})."
                else:
                    generation = f"Couldn't update threshold: {res.get('error')}"

        state["executed_actions"] = executed_actions
        state["generation"] = generation
    else:
        content = extract_text_content(response.content)
        state["generation"] = content or "Done! Everything is set."

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

    return None


def analytics_agent_node(state: GraphState) -> GraphState:
    """Calculates live analytics, stockout risks, and financial valuations from DB and uses LLM to answer."""
    question = state["question"]
    company_id = state.get("company_id", "default")
    metrics = db_instance.get_analytics_summary(company_id=company_id)
    autopilot_recs = db_instance.run_autopilot_scan(company_id=company_id)
    all_products = db_instance.get_all_products(company_id=company_id)

    # Compute ML analytics
    abc_analysis = perform_abc_analysis(all_products)
    risk_timelines = [calculate_stockout_risk_timeline(p) for p in all_products if p.get("stock", 0) <= p.get("min_threshold", 10)]

    llm_pro = get_active_llm(temperature=0.2)
    if not llm_pro:
        content = _generate_instant_table_response("summary", metrics, autopilot_recs, company_id=company_id) or "Inventory analytics updated."
    else:
        context_str = (
            f"INVENTORY METRICS SUMMARY:\n"
            f"- Total Products: {metrics['total_products']}\n"
            f"- Low Stock Count: {metrics['low_stock_count']}\n"
            f"- Out of Stock Count: {metrics['out_of_stock_count']}\n"
            f"- Total Selling Valuation: ${metrics['total_inventory_value']:,.2f}\n"
            f"- Total Cost Valuation: ${metrics['total_cost_value']:,.2f}\n"
            f"- Autopilot Reorder Recommendations: {autopilot_recs}\n\n"
            f"MACHINE LEARNING INSIGHTS:\n"
            f"- ABC Analysis (Top 80% Rev, Middle 15%, Bottom 5%):\n"
            f"  - Category A count: {len(abc_analysis['A'])}\n"
            f"  - Category B count: {len(abc_analysis['B'])}\n"
            f"  - Category C count: {len(abc_analysis['C'])}\n"
            f"- Stockout Risks (Critical/Warning):\n"
            f"  {json.dumps(risk_timelines, indent=2)}\n"
        )

        prompt = ChatPromptTemplate.from_messages([
            ("system", "You are a sharp, analytical inventory manager.\n"
                       "CRITICAL INSTRUCTIONS:\n"
                       "1. Answer the user's specific analytics question based on the provided metrics and ML insights.\n"
                       "2. If they ask for tables, summaries, or reports, generate clean markdown tables.\n"
                       "3. If they ask about stockout risks or ABC analysis, use the provided ML insights to answer.\n"
                       "4. Never hallucinate data. If data is not present, say so clearly.\n"
                       "5. Strictly NO AI clichés ('As an AI', etc.)."),
            ("user", "Metrics & ML Data:\n{context}\nUser Question: {question}")
        ])

        messages = prompt.format_messages(context=context_str, question=question)
        try:
            response = llm_pro.invoke(messages)
            content = extract_text_content(response.content)
        except Exception as e:
            print(f"[Analytics Node] LLM invoke failed: {e}")
            content = _generate_instant_table_response("summary", metrics, autopilot_recs, company_id=company_id) or "Inventory analytics updated."

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
    company_id = state.get("company_id", "default")
    docs_text = "\n\n".join(doc.page_content for doc in documents if hasattr(doc, 'page_content'))

    metrics = db_instance.get_analytics_summary(company_id=company_id)
    autopilot_recs = db_instance.run_autopilot_scan(company_id=company_id)

    # Check for instant table response match first
    instant_table = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)

    if instant_table:
        state["generation"] = instant_table
        return state

    q = question.lower()
    tinker_key = os.environ.get("TINKER_API_KEY")


    # 1. Business Growth / Revenue / Sales Strategy Questions
    if any(k in q for k in ["increase my business", "grow", "growth", "boost sales", "revenue", "strategy", "improve sales", "marketing", "20%"]):
        content = (
            "Here are 5 high-impact strategies to grow your retail business revenue by 20%:\n\n"
            "| Strategy | Actionable Execution | Expected Impact |\n"
            "| :--- | :--- | :--- |\n"
            "| **1. Zero Stockouts on High-Velocity Items** | Restock top-selling products 3 days before hitting min safety threshold | **+8% Revenue** (eliminates lost sales) |\n"
            "| **2. Strategic Product Bundling** | Pair slow-moving stock with high-demand essentials at a 5% bundle discount | **+5% Average Basket Value** |\n"
            "| **3. Optimize Supplier Lead Times** | Negotiate shorter vendor fulfillment windows to reduce safety stock holding costs | **+4% Cash Flow Efficiency** |\n"
            "| **4. Customer Loyalty Re-order Reminders** | Send timely replenishment alerts for fast-consuming consumables | **+3% Repeat Purchase Rate** |\n"
            "| **5. Liquidate Dead Stock** | Clearance-sale items with zero sales in 60+ days to free capital for fast movers | **Instant Cash Recovery** |\n\n"
            "Would you like me to analyze your fast-moving items or create purchase orders for low-stock products to support your growth plan?"
        )
    # 2. Friendly human fallback for greetings / self-introductions / capability questions
    elif any(k in q for k in ["tell me about yourself", "who are you", "what can you do", "what are you", "what is ask ai", "hello", "hi", "hey"]):
        content = (
            "Hi! I'm **Ask AI**, your intelligent inventory assistant.\n\n"
            "Here is how I can help manage your store:\n\n"
            "| Capability | How I Help |\n"
            "| :--- | :--- |\n"
            "| **Stock Actions** | Add/deduct stock, process transfers, or run physical audits |\n"
            "| **Purchase Orders** | Auto-generate purchase orders based on sales velocity |\n"
            "| **Health Audits** | Flag low-stock risks and calculate real-time inventory valuation |\n"
            "| **Business Intelligence** | Provide actionable growth strategies and stock analytics |\n\n"
            "Ask me a question or tell me what action to take!"
        )
    else:
        llm_knowledge = get_active_llm(temperature=0.3)
        if llm_knowledge:
            company_data = db_instance._get_company(company_id=company_id)
            action_ledger = company_data.get("action_ledger", [])
            recent_ledger = list(reversed(action_ledger[-15:]))
            
            context_str = docs_text + "\n\n" + f"RECENT TRANSACTION HISTORY (Action Ledger):\n{json.dumps(recent_ledger, indent=2)}"

            prompt = ChatPromptTemplate.from_messages([
                ("system", "You are a warm, sharp, highly intelligent business and stock management assistant helping a store owner.\n"
                           "CRITICAL INSTRUCTIONS:\n"
                           "1. Directly answer the user's specific question with practical, intelligent advice.\n"
                           "2. Speak naturally like a human colleague—warm, practical, concise, and clear.\n"
                           "3. Use the RECENT TRANSACTION HISTORY to answer questions about past actions, purchase orders, or stock changes.\n"
                           "4. Strictly NO AI clichés, no generic disclaimers ('As an AI...', 'I cannot...').\n"
                           "5. Format structural lists or guides in clean markdown tables or short bullet points."),
                ("user", "Context:\n{context}\nQuestion: {question}")
            ])
            
            messages = prompt.format_messages(context=context_str, question=question)
            try:
                response = llm_knowledge.invoke(messages)
                content = extract_text_content(response.content)
            except Exception as e:
                print(f"[Knowledge Node] LLM invoke failed: {e}")
                content = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)
                if not content:
                    content = (
                        "Here is an overview of your store operations:\n\n"
                        f"- **Registered Products**: **{metrics['total_products']}** items\n"
                        f"- **Low Stock Warnings**: **{metrics['low_stock_count']}** items\n"
                        f"- **Out of Stock**: **{metrics['out_of_stock_count']}** items\n"
                        f"- **Inventory Valuation**: **${metrics['total_inventory_value']:,.2f}**\n\n"
                        "How can I assist you with your inventory or sales plan?"
                    )
        else:
            content = _generate_instant_table_response(question, metrics, autopilot_recs, company_id=company_id)
            if not content:
                content = (
                    "Here is your current store overview:\n\n"
                    f"- **Registered Products**: **{metrics['total_products']}** items\n"
                    f"- **Low Stock Warnings**: **{metrics['low_stock_count']}** items\n"
                    f"- **Out of Stock**: **{metrics['out_of_stock_count']}** items\n"
                    f"- **Inventory Valuation**: **${metrics['total_inventory_value']:,.2f}**\n\n"
                    "Tell me if you'd like me to perform an audit, restock low items, or update stock!"
                )


    state["generation"] = content
    return state


# Compatibility aliases
retrieve = retrieve_node
generate = action_agent_node
