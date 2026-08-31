import re
from typing import Dict, Any

from facts import fact_store
from resolver import resolve_product
import writes

def process_voice_command(speech_text: str, company_id: str) -> Dict[str, Any]:
    """
    Parses spoken natural language commands (e.g. 'Deduct 15 units of Fresh Apples damaged')
    and executes atomic stock mutations with audio confirmation feedback.
    """
    speech_text_lower = speech_text.lower()
    
    # Extract numerical quantity using regex
    qty_matches = re.findall(r'\b\d+\b', speech_text_lower)
    qty = int(qty_matches[0]) if qty_matches else 1

    is_deduct = any(w in speech_text_lower for w in ["deduct", "remove", "damaged", "sold", "subtract", "minus", "reduce"])
    is_add = any(w in speech_text_lower for w in ["add", "received", "restock", "increment", "plus"])
    is_audit = any(w in speech_text_lower for w in ["audit", "count", "physical"])

    # Load facts and resolve product
    facts = fact_store.get(company_id)
    resolution = resolve_product(speech_text_lower, facts)

    if resolution.status == "not_found":
        return {
            "status": "error",
            "audio_response_text": f"Could not find any inventory item matching '{speech_text}'.",
            "execution_result": None
        }
    
    if resolution.status == "ambiguous":
        # Voice ambiguous match
        candidates_text = " or ".join([c.name for c in resolution.candidates[:2]])
        return {
            "status": "ambiguous",
            "audio_response_text": f"Did you mean {candidates_text}?",
            "execution_result": None
        }
        
    target_prod = resolution.product

    if is_audit and target_prod:
        res = writes.audit_inventory(target_prod, qty, f"Voice AI Audit: {speech_text}", company_id=company_id)
        if res.get("success", False):
            audio_text = f"Voice Audit Completed: {target_prod.name} stock updated to {qty} units."
            status = "success"
        else:
            audio_text = f"Could not audit {target_prod.name}: {res.get('error', 'Audit failed')}."
            status = "error"
        return {
            "status": status,
            "action": "voice_audit",
            "audio_response_text": audio_text,
            "execution_result": res
        }
    elif is_deduct and target_prod:
        res = writes.update_stock(target_prod, -qty, f"Voice AI Deduction: {speech_text}", company_id=company_id)
        if res.get("success", False):
            new_stk = res.get("new_stock", 0)
            audio_text = f"Updated: Deducted {qty} units of {target_prod.name}. Remaining stock: {new_stk}."
            status = "success"
        else:
            audio_text = f"Could not deduct {qty} units of {target_prod.name}: {res.get('error', 'Insufficient stock')}."
            status = "error"
        return {
            "status": status,
            "action": "voice_deduct",
            "audio_response_text": audio_text,
            "execution_result": res
        }
    elif (is_add or not is_deduct) and target_prod:
        res = writes.update_stock(target_prod, qty, f"Voice AI Addition: {speech_text}", company_id=company_id)
        if res.get("success", False):
            new_stk = res.get("new_stock", 0)
            audio_text = f"Updated: Added {qty} units to {target_prod.name}. Total stock: {new_stk}."
            status = "success"
        else:
            audio_text = f"Could not add {qty} units to {target_prod.name}: {res.get('error', 'Update failed')}."
            status = "error"
        return {
            "status": status,
            "action": "voice_add",
            "audio_response_text": audio_text,
            "execution_result": res
        }

    return {
        "status": "ERROR",
        "audio_response_text": f"Could not match product in speech command: '{speech_text}'. Please specify product name.",
        "execution_result": None
    }
