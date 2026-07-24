"""
Guardrails Module for Autonomous AI Inventory Actions.
Enforces strict business policies, financial spending limits, and database safety rules.
"""

from typing import Dict, Any, List, Optional
from dataclasses import dataclass

AUTO_APPROVE_MAX_COST = 1000.0  # Max USD for auto-approval without human sign-off
MIN_STOCK_FLOOR = 0             # Stock can never be updated to negative values
MAX_SINGLE_ITEM_REORDER = 10000 # Max units for a single item reorder

@dataclass
class GuardrailResult:
    passed: bool
    requires_human_approval: bool
    risk_level: str  # "LOW", "MEDIUM", "HIGH", "CRITICAL"
    reasons: List[str]
    sanitized_payload: Dict[str, Any]

class InventoryGuardrails:
    def __init__(self, max_auto_cost: float = AUTO_APPROVE_MAX_COST):
        self.max_auto_cost = max_auto_cost

    def validate_action(self, action_type: str, payload: Dict[str, Any], current_db_item: Optional[Dict[str, Any]] = None) -> GuardrailResult:
        reasons = []
        requires_human = False
        risk_level = "LOW"
        sanitized = dict(payload)

        if action_type in ["create_reorder_po", "reorder_stock"]:
            qty = payload.get("quantity", 0)
            cost_per_unit = payload.get("cost_price", payload.get("unit_cost", 0.0))
            
            if current_db_item and cost_per_unit == 0.0:
                cost_per_unit = current_db_item.get("cost_price", 0.0)
                sanitized["cost_price"] = cost_per_unit
                
            total_cost = qty * cost_per_unit
            sanitized["total_cost"] = total_cost

            if qty <= 0:
                reasons.append(f"Invalid reorder quantity: {qty}. Must be > 0.")
                return GuardrailResult(False, True, "CRITICAL", reasons, sanitized)

            if qty > MAX_SINGLE_ITEM_REORDER:
                reasons.append(f"Reorder quantity {qty} exceeds max single order ceiling of {MAX_SINGLE_ITEM_REORDER}.")
                requires_human = True
                risk_level = "HIGH"

            if total_cost > self.max_auto_cost:
                reasons.append(f"Total PO cost ${total_cost:.2f} exceeds auto-approval threshold of ${self.max_auto_cost:.2f}.")
                requires_human = True
                risk_level = "MEDIUM" if risk_level == "LOW" else risk_level

        elif action_type == "update_stock":
            new_stock = payload.get("new_stock", 0)
            if new_stock < MIN_STOCK_FLOOR:
                reasons.append(f"Target stock {new_stock} violates min stock floor of {MIN_STOCK_FLOOR}.")
                return GuardrailResult(False, True, "CRITICAL", reasons, sanitized)

            if current_db_item:
                old_stock = current_db_item.get("stock", 0)
                diff = abs(new_stock - old_stock)
                if old_stock > 0 and (diff / old_stock) > 2.0 and diff > 50:
                    reasons.append(f"Stock change from {old_stock} to {new_stock} is a massive anomaly (>200% change).")
                    requires_human = True
                    risk_level = "HIGH"

        elif action_type == "update_price":
            new_price = payload.get("selling_price", 0.0)
            cost_price = payload.get("cost_price", 0.0)
            if current_db_item:
                cost_price = cost_price or current_db_item.get("cost_price", 0.0)

            if new_price < cost_price:
                reasons.append(f"Selling price ${new_price:.2f} is below cost price ${cost_price:.2f} (negative margin).")
                requires_human = True
                risk_level = "HIGH"

        passed = True if not reasons or requires_human else False
        if any("Invalid" in r or "violates" in r for r in reasons):
            passed = False

        return GuardrailResult(
            passed=passed,
            requires_human_approval=requires_human,
            risk_level=risk_level,
            reasons=reasons,
            sanitized_payload=sanitized
        )
