"""
Autonomous Multi-Agent Swarm for Inventory Management.
Integrates Planner, Code Engine, Guardrail, and Reflection Agents into a closed-loop ReAct system.
Supports tenant isolation per company_id.
"""

import time
import collections
from typing import Dict, Any, List, Optional
try:
    from .inventory_db import InventoryDB
    from .guardrails import InventoryGuardrails, GuardrailResult
    from .predictive_ml import calculate_eoq, calculate_reorder_point, predict_days_until_stockout
except ImportError:
    from inventory_db import InventoryDB
    from guardrails import InventoryGuardrails, GuardrailResult
    from predictive_ml import calculate_eoq, calculate_reorder_point, predict_days_until_stockout



class AutonomousSwarm:
    def __init__(self, db: Optional[InventoryDB] = None):
        self.db = db or InventoryDB()
        self.guardrails = InventoryGuardrails()
        self.episodic_memory: collections.deque = collections.deque(maxlen=200)
        self.pending_pos: Dict[str, Dict[str, Any]] = {}

    def refresh_engine(self, company_id: str = "default") -> List[Dict[str, Any]]:
        """Load the swarm's working set from the fact layer.

        Previously this read a local dict where `sales_velocity` was always 0,
        so EOQ, ROP and the clearance agent were all computing on placeholders.
        These rows carry real burn rates derived from the transaction ledger.
        """
        from facts import fact_store

        facts = fact_store.get(company_id)
        rows = [
            {
                "barcode": p.barcode,
                "name": p.name,
                "stock": p.quantity,
                "available": p.available_qty,
                "min_threshold": p.min_threshold,
                "cost_price": p.cost_price,
                "selling_price": p.selling_price,
                # Daily, matching predictive_ml's convention.
                "sales_velocity": p.daily_burn_rate,
                "lead_time_days": p.lead_time_days,
                "health": p.health,
                "days_of_supply": p.days_of_supply,
                "reorder_point": p.reorder_point,
                "suggested_reorder_qty": p.suggested_reorder_qty,
            }
            for p in facts.products
        ]
        return rows

    def run_full_autopilot_sweep(self, company_id: str = "default") -> Dict[str, Any]:
        """
        24/7 Proactive Autonomous Background Sweep.
        Runs Batch Auto-Reorder, Stock Decay/Idle Clearance, and Supplier Cost Variance agents for company_id.
        """
        all_prods = self.refresh_engine(company_id=company_id)
        sweep_log = {
            "timestamp": time.time(),
            "reorders_processed": [],
            "clearance_recommendations": [],
            "supplier_alerts": []
        }

        # 1. BATCH AUTO-REORDER AGENT
        low_stock_items = [p for p in all_prods if p.get('stock', 0) <= p.get('min_threshold', 10)]
        for product in low_stock_items:
            annual_demand = max(1.0, product.get("sales_velocity", 1.0)) * 365
            cost_price = max(1.0, product.get("cost_price", 10.0))
            eoq = calculate_eoq(annual_demand=annual_demand, holding_cost_per_unit=cost_price * 0.15)
            lead_time = product.get("lead_time_days", 3)
            rop = calculate_reorder_point(avg_daily_sales=product.get("sales_velocity", 1.0), lead_time_days=lead_time)

            po_payload = {
                "barcode": product.get("barcode"),
                "name": product.get("name"),
                "quantity": eoq,
                "cost_price": cost_price,
                "suggested_rop": rop
            }

            guardrail_res: GuardrailResult = self.guardrails.validate_action("create_reorder_po", po_payload, product)
            po_id = f"PO-{product.get('barcode')}-{int(eoq)}"

            if guardrail_res.passed:
                if not guardrail_res.requires_human_approval:
                    self.db.add_action_log(
                        action_type="AUTONOMOUS_REORDER_PO",
                        details=guardrail_res.sanitized_payload,
                        user="AI_SWARM_AGENT"
                    )
                    msg = f"Autonomous PO of {eoq} units created automatically for '{product.get('name')}'."
                else:
                    self.pending_pos[po_id] = {
                        "po_id": po_id,
                        "product_name": product.get("name"),
                        "barcode": product.get("barcode"),
                        "quantity": eoq,
                        "total_cost": round(eoq * cost_price, 2),
                        "status": "QUEUED_FOR_APPROVAL",
                        "reasons": guardrail_res.reasons
                    }
                    msg = f"PO drafted for '{product.get('name')}' (${round(eoq * cost_price, 2):,.2f}). Queued for approval (ID: {po_id})."
            else:
                msg = f"PO blocked by guardrails: {', '.join(guardrail_res.reasons)}"

            log_item = {
                "po_id": po_id,
                "product": product.get("name"),
                "status": msg,
                "requires_approval": guardrail_res.requires_human_approval
            }
            sweep_log["reorders_processed"].append(log_item)
            self.episodic_memory.append(log_item)

        # 2. STOCK DECAY & IDLE CLEARANCE AGENT
        for p in all_prods:
            stock = p.get("stock", 0)
            velocity = p.get("sales_velocity", 0)
            # Only genuine dead stock. A product whose movement is not being
            # recorded looks identical to one that never sells, and marking it
            # down would be acting on missing data rather than evidence.
            if stock > 20 and p.get("health") == "dead_stock":
                rec_discount = 20  # Recommend 20% clearance markdown
                rec_item = {
                    "barcode": p.get("barcode"),
                    "name": p.get("name"),
                    "current_stock": stock,
                    "sales_velocity": velocity,
                    "recommended_discount_pct": rec_discount,
                    "action": f"Apply {rec_discount}% discount on '{p.get('name')}' to accelerate slow-moving inventory."
                }
                sweep_log["clearance_recommendations"].append(rec_item)
                self.episodic_memory.append({"event": "CLEARANCE_RECOMMENDATION", "details": rec_item})

        # 3. SUPPLIER COST & VARIANCE WATCH AGENT
        for p in all_prods:
            cost = p.get("cost_price", 0)
            sell = p.get("selling_price", 0)
            if sell > 0 and (cost / sell) > 0.8:
                sup_alert = {
                    "barcode": p.get("barcode"),
                    "name": p.get("name"),
                    "cost_price": cost,
                    "selling_price": sell,
                    "margin_pct": round((1 - (cost / sell)) * 100, 1),
                    "recommendation": f"Low margin alert on '{p.get('name')}'. Negotiate vendor discount or raise price."
                }
                sweep_log["supplier_alerts"].append(sup_alert)
                self.episodic_memory.append({"event": "SUPPLIER_MARGIN_ALERT", "details": sup_alert})

        return sweep_log

    def approve_pending_po(self, po_id: str, company_id: str = "default") -> Dict[str, Any]:
        """
        1-Click Human Approval for queued high-value Purchase Orders.
        """
        if po_id not in self.pending_pos:
            return {"status": "ERROR", "message": f"PO ID '{po_id}' not found in pending queue."}
        
        po_data = self.pending_pos[po_id]
        
        # Pre-validation check: Does the product still exist?
        barcode = po_data.get("barcode")
        if barcode:
            product = self.db.get_product(barcode, company_id=company_id)
            if not product:
                return {"status": "ERROR", "message": f"Cannot approve PO '{po_id}': Product '{barcode}' no longer exists in inventory."}
                
        self.pending_pos.pop(po_id)
        
        self.db.add_action_log(
            action_type="APPROVED_REORDER_PO",
            details=po_data,
            user="MANAGER_HUMAN_APPROVAL"
        )
        log_entry = {"event": "PO_APPROVED", "po_id": po_id, "po_data": po_data}
        self.episodic_memory.append(log_entry)
        return {"status": "APPROVED", "message": f"Purchase Order '{po_id}' approved & executed.", "po_data": po_data}

    def process_event_trigger(self, event_name: str, payload: Dict[str, Any], company_id: str = "default") -> Dict[str, Any]:
        """
        Proactive autonomous loop triggered by background events (e.g. stock drop, low inventory alert).
        """
        self.refresh_engine(company_id=company_id)
        
        if event_name in ["LOW_STOCK_TRIGGER", "STOCKOUT_RISK"]:
            sweep = self.run_full_autopilot_sweep(company_id=company_id)
            # Always return the same envelope shape, whatever the event.
            return {"status": "SWEEP_COMPLETED", "event": event_name, **sweep}

        return {"status": "UNKNOWN_EVENT", "event": event_name}

    def process_query(self, query: str, company_id: str = "default") -> Dict[str, Any]:
        """
        Fast, deterministic query processor over the fact snapshot.

        This used to run pandas over a local dict and cache results behind a
        bag-of-words similarity check. The rows come from `facts.py` now, so the
        classifications (health, reorder point) are already computed and these
        are sub-millisecond list comprehensions — there is nothing worth caching,
        and caching risked serving one query's answer for another's.
        """
        all_items = self.refresh_engine(company_id=company_id)
        query_lower = query.lower()

        if "low stock" in query_lower or "reorder" in query_lower:
            items = [
                p for p in all_items
                if p.get("stock", 0) <= p.get("min_threshold", 10)
                or p.get("suggested_reorder_qty", 0) > 0
            ]
            result = {
                "type": "LOW_STOCK_ANALYSIS",
                "count": len(items),
                "items": items,
                "summary": f"Found {len(items)} items requiring immediate restock."
            }
        elif "risk" in query_lower or "urgent" in query_lower:
            # Sort by days_left ascending, then inventory_value descending
            items = sorted(
                all_items,
                key=lambda x: (
                    x.get('stock', 0) / max(x.get('sales_velocity', 1.0) or 0.1, 0.1),
                    - (x.get('stock', 0) * x.get('cost_price', 0.0))
                )
            )[:5]
            result = {
                "type": "RISK_ANALYSIS",
                "count": len(items),
                "items": items,
                "summary": f"Top {len(items)} high-value items at risk of stockout identified."
            }
        else:
            total_value = sum(i.get("stock", 0) * i.get("selling_price", 0) for i in all_items)
            result = {
                "type": "GENERAL_SUMMARY",
                "total_items": len(all_items),
                "total_inventory_value": round(total_value, 2),
                "summary": f"Inventory contains {len(all_items)} total SKUs valued at ${total_value:,.2f}."
            }

        return result
