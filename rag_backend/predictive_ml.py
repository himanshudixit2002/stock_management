"""
Predictive ML & Optimization Math Module.
Fast deterministic algorithms for inventory optimization (EOQ, ROP, Safety Stock, ABC analysis).
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

def calculate_safety_stock(max_daily_sales: float, max_lead_time: int, avg_daily_sales: float, avg_lead_time: int) -> int:
    """
    Safety Stock = (Max Daily Sales * Max Lead Time) - (Avg Daily Sales * Avg Lead Time)
    """
    max_usage = max_daily_sales * max_lead_time
    avg_usage = avg_daily_sales * avg_lead_time
    safety_stock = max_usage - avg_usage
    return max(0, round(safety_stock))

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

def calculate_statistical_safety_stock(avg_daily_sales: float, lead_time_days: int, std_dev: Optional[float] = None, z_factor: float = 1.65) -> int:
    """
    Statistical Safety Stock = Z * (std_dev_daily) * sqrt(lead_time_days)
    Default Z = 1.65 corresponds to 95% service level fulfillment rate.
    """
    if avg_daily_sales <= 0 or lead_time_days <= 0:
        return 0
    sigma = std_dev if (std_dev is not None and std_dev > 0) else (avg_daily_sales * 0.3)
    safety_stock = z_factor * sigma * math.sqrt(lead_time_days)
    return max(1, round(safety_stock))

def predict_30day_demand_forecast(product: Dict[str, Any], days: int = 30) -> List[Dict[str, Any]]:
    """
    Generates a 30-day daily time-series demand projection including day-of-week seasonality (1.25x weekend surge)
    and projected remaining stock trajectory.
    """
    base_velocity = float(product.get("sales_velocity", 1.0))
    current_stock = float(product.get("stock", 0))
    
    daily_projections = []
    accumulated_demand = 0.0
    remaining_stock = current_stock

    for day in range(1, days + 1):
        # Weekend multiplier (Day 6 & 7 of 7-day cycle)
        multiplier = 1.25 if (day % 7 in [6, 0]) else 1.0
        projected_day_sales = round(base_velocity * multiplier, 1)
        
        accumulated_demand += projected_day_sales
        remaining_stock = max(0.0, round(current_stock - accumulated_demand, 1))

        daily_projections.append({
            "day": day,
            "projected_daily_demand": projected_day_sales,
            "cumulative_demand": round(accumulated_demand, 1),
            "projected_remaining_stock": remaining_stock,
            "is_stockout": remaining_stock == 0.0
        })

    return daily_projections

def calculate_stockout_risk_timeline(product: Dict[str, Any]) -> Dict[str, Any]:
    """
    Evaluates exact stockout risk timeline, risk category (CRITICAL / WARNING / OPTIMAL),
    and monetary revenue at risk using real product velocity.
    """
    stock = float(product.get("stock", 0))
    raw_velocity = float(product.get("sales_velocity", 0.0))
    lead_time = int(product.get("lead_time_days", 3))
    selling_price = float(product.get("selling_price", product.get("cost_price", 10.0)))

    if stock == 0:
        risk_level = "CRITICAL"
        days_left = 0.0
        recommendation = f"URGENT: '{product.get('name')}' is completely out of stock (0 units). Immediate reorder required."
        unmet_units = max(10, int(product.get("min_threshold", 10)))
        revenue_at_risk = round(unmet_units * selling_price, 2)
    elif raw_velocity <= 0.0:
        min_th = int(product.get("min_threshold", 10))
        if stock <= min_th:
            risk_level = "WARNING"
            days_left = round(stock / 0.5, 1)
            recommendation = f"Low stock warning: {int(stock)} units remaining (below threshold {min_th})."
            revenue_at_risk = round(stock * selling_price, 2)
        else:
            risk_level = "OPTIMAL"
            days_left = 999.0
            recommendation = f"Stock is healthy ({int(stock)} units in stock, zero recent depletion)."
            revenue_at_risk = 0.0
    else:
        days_left = round(stock / raw_velocity, 1)
        if days_left <= lead_time:
            risk_level = "CRITICAL"
            recommendation = f"URGENT: Stockout expected in {days_left} days (Lead time: {lead_time} days). Immediate PO required."
        elif days_left <= (lead_time * 2):
            risk_level = "WARNING"
            recommendation = f"Stockout predicted in {days_left} days. Reorder within 48 hours."
        else:
            risk_level = "OPTIMAL"
            recommendation = f"Stock level is optimal ({days_left} days of inventory remaining at current velocity)."

        unmet_units = max(0, round((lead_time * raw_velocity) - stock))
        revenue_at_risk = round(unmet_units * selling_price, 2)

    return {
        "barcode": product.get("barcode"),
        "name": product.get("name"),
        "current_stock": int(stock),
        "days_until_stockout": days_left,
        "lead_time_days": lead_time,
        "risk_level": risk_level,
        "revenue_at_risk": revenue_at_risk,
        "recommendation": recommendation
    }

def perform_abc_analysis(products: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Categorizes products into A (Top 80% revenue value), B (Next 15%), C (Bottom 5%).
    """
    if not products:
        return {"A": [], "B": [], "C": []}

    items_with_val = []
    for item in products:
        sales_vel = item.get("sales_velocity", 1.0)
        cost = item.get("selling_price", item.get("cost_price", 10.0))
        annual_val = sales_vel * 365 * cost
        items_with_val.append((annual_val, item))

    items_with_val.sort(key=lambda x: x[0], reverse=True)
    total_val = sum(x[0] for x in items_with_val) or 1.0

    cumulative = 0.0
    category_a, category_b, category_c = [], [], []

    for idx, (annual_val, item) in enumerate(items_with_val):
        item_copy = dict(item)
        if idx == 0 or (cumulative / total_val) < 0.80:
            item_copy["abc_category"] = "A"
            category_a.append(item_copy)
        elif (cumulative / total_val) < 0.95:
            item_copy["abc_category"] = "B"
            category_b.append(item_copy)
        else:
            item_copy["abc_category"] = "C"
            category_c.append(item_copy)
        cumulative += annual_val

    return {
        "A": category_a,
        "B": category_b,
        "C": category_c
    }


