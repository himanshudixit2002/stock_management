import re

with open('rag_backend/agent_swarm.py', 'r') as f:
    content = f.read()

# Remove code_engine import
content = re.sub(r'from .code_engine import InventoryCodeEngine\n?', '', content)
content = re.sub(r'from code_engine import InventoryCodeEngine\n?', '', content)

# Remove code_engine initialization
content = content.replace("        self.code_engine = InventoryCodeEngine([])\n", "")

# Remove code_engine from refresh_engine
content = content.replace("        self.code_engine.update_data(rows)\n", "")

# Fix run_full_autopilot_sweep to use facts directly
content = content.replace("        low_stock_items = self.code_engine.get_low_stock_items()", "        low_stock_items = [p for p in all_prods if p.get('stock', 0) <= p.get('min_threshold', 10)]")

# Fix process_query to use facts directly
old_process_query = """        if "low stock" in query_lower or "reorder" in query_lower:
            items = self.code_engine.get_low_stock_items()
            result = {
                "type": "LOW_STOCK_ANALYSIS",
                "count": len(items),
                "items": items,
                "summary": f"Found {len(items)} items requiring immediate restock."
            }
        elif "risk" in query_lower or "urgent" in query_lower:
            items = self.code_engine.get_highest_value_risk_items()
            result = {
                "type": "RISK_ANALYSIS",
                "count": len(items),
                "items": items,
                "summary": f"Top {len(items)} high-value items at risk of stockout identified."
            }"""

new_process_query = """        if "low stock" in query_lower or "reorder" in query_lower:
            items = [p for p in all_prods if p.get('stock', 0) <= p.get('min_threshold', 10)]
            result = {
                "type": "LOW_STOCK_ANALYSIS",
                "count": len(items),
                "items": items,
                "summary": f"Found {len(items)} items requiring immediate restock."
            }
        elif "risk" in query_lower or "urgent" in query_lower:
            # Sort by days_left ascending, then inventory_value descending
            items = sorted(
                all_prods,
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
            }"""

content = content.replace(old_process_query, new_process_query)

with open('rag_backend/agent_swarm.py', 'w') as f:
    f.write(content)
