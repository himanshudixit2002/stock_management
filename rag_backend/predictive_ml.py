"""
Predictive ML & Optimization Math Module.
Fast deterministic algorithms for inventory optimization (EOQ, ROP).
"""

import math
from typing import Dict, Any, List, Optional


def calculate_eoq(annual_demand: float, ordering_cost: float = 50.0, holding_cost_per_unit: float = 2.0) -> int:
    """
    Economic Order Quantity (EOQ) formula:
    EOQ = sqrt((2 * D * S) / H)
    """
    if annual_demand <= 0 or holding_cost_per_unit <= 0:
        return 0
    eoq = math.sqrt((2 * annual_demand * ordering_cost) / holding_cost_per_unit)
    return max(1, round(eoq))

def calculate_reorder_point(avg_daily_sales: float, lead_time_days: int, safety_stock: int = 0) -> int:
    """
    Reorder Point (ROP) = (Avg Daily Sales * Lead Time) + Safety Stock
    """
    rop = (avg_daily_sales * lead_time_days) + safety_stock
    return max(1, round(rop))

def predict_days_until_stockout(current_stock: int, sales_velocity_per_day: float) -> float:
    """
    Days until stockout = current_stock / sales_velocity
    """
    if sales_velocity_per_day <= 0:
        return 999.0  # Essentially infinite days if velocity is zero
    return round(current_stock / sales_velocity_per_day, 1)

