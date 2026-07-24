"""
Dynamic Pandas Code Execution Engine.
Runs sub-millisecond vectorized pandas queries on inventory datasets safely.
"""

import pandas as pd
import math
from typing import Dict, Any, List, Optional

def _sanitize_value(v: Any) -> Any:
    if isinstance(v, float) and math.isnan(v):
        return None
    return v

class InventoryCodeEngine:
    def __init__(self, products: List[Dict[str, Any]]):
        self.df = pd.DataFrame(products) if products else pd.DataFrame()

    def update_data(self, products: List[Dict[str, Any]]):
        self.df = pd.DataFrame(products) if products else pd.DataFrame()

    def _to_clean_records(self, df_sub: pd.DataFrame) -> List[Dict[str, Any]]:
        raw_records = df_sub.to_dict(orient="records")
        clean_records = []
        for rec in raw_records:
            clean_rec = {k: _sanitize_value(v) for k, v in rec.items()}
            clean_records.append(clean_rec)
        return clean_records

    def get_low_stock_items(self, threshold_multiplier: float = 1.0) -> List[Dict[str, Any]]:
        if self.df.empty:
            return []
        mask = self.df["stock"] <= (self.df["min_threshold"] * threshold_multiplier)
        return self._to_clean_records(self.df[mask])

    def get_highest_value_risk_items(self, limit: int = 5) -> List[Dict[str, Any]]:
        if self.df.empty:
            return []
        df_copy = self.df.copy()
        df_copy["inventory_value"] = df_copy["stock"] * df_copy["cost_price"]
        df_copy["days_left"] = df_copy.apply(
            lambda r: r["stock"] / max(r.get("sales_velocity", 1.0) or 0.1, 0.1), axis=1
        )
        sorted_df = df_copy.sort_values(by=["days_left", "inventory_value"], ascending=[True, False])
        return self._to_clean_records(sorted_df.head(limit))

    def execute_custom_pandas_query(self, query_expression: str) -> List[Dict[str, Any]]:
        if self.df.empty:
            return []
        try:
            result_df = self.df.query(query_expression)
            return self._to_clean_records(result_df)
        except Exception as e:
            print(f"Error executing pandas query '{query_expression}': {e}")
            return []
