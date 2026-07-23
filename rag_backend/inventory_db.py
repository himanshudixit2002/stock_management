import json
import os
from typing import Dict, List, Optional, Any
from datetime import datetime

DB_FILE = os.path.join(os.path.dirname(__file__), "inventory_db.json")

class InventoryDB:
    def __init__(self, db_path: str = DB_FILE):
        self.db_path = db_path
        self.products: Dict[str, Dict[str, Any]] = {}
        self.action_ledger: List[Dict[str, Any]] = []
        self._load()

    def _load(self):
        if os.path.exists(self.db_path):
            try:
                with open(self.db_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.products = data.get("products", {})
                    self.action_ledger = data.get("action_ledger", [])
            except Exception as e:
                print(f"Error loading inventory DB: {e}")
                self._seed_default_data()
        else:
            self._seed_default_data()

    def _save(self):
        try:
            with open(self.db_path, "w", encoding="utf-8") as f:
                json.dump({
                    "products": self.products,
                    "action_ledger": self.action_ledger
                }, f, indent=2)
        except Exception as e:
            print(f"Error saving inventory DB: {e}")

    def _seed_default_data(self):
        default_items = [
            {
                "barcode": "89010001",
                "name": "Fresh Apples (kg)",
                "stock": 15,
                "min_threshold": 50,
                "category": "Produce",
                "cost_price": 1.20,
                "selling_price": 2.50,
                "sales_velocity": 40,
                "lead_time_days": 3,
                "location": "Store Front - A1"
            },
            {
                "barcode": "89010002",
                "name": "Pro Laptops (15-inch)",
                "stock": 100,
                "min_threshold": 20,
                "category": "Electronics",
                "cost_price": 650.00,
                "selling_price": 999.00,
                "sales_velocity": 10,
                "lead_time_days": 14,
                "location": "Warehouse B - Shelf 4"
            },
            {
                "barcode": "89010003",
                "name": "Sparkling Water (Pack of 12)",
                "stock": 200,
                "min_threshold": 100,
                "category": "Beverages",
                "cost_price": 4.00,
                "selling_price": 8.99,
                "sales_velocity": 150,
                "lead_time_days": 1,
                "location": "Store Front - C3"
            },
            {
                "barcode": "89010004",
                "name": "Organic Whole Milk (1L)",
                "stock": 8,
                "min_threshold": 30,
                "category": "Dairy",
                "cost_price": 1.50,
                "selling_price": 2.99,
                "sales_velocity": 25,
                "lead_time_days": 2,
                "location": "Chiller 2"
            }
        ]
        for item in default_items:
            self.products[item["barcode"]] = item
        self._save()

    def replace_user_inventory(self, custom_products: List[Dict[str, Any]]):
        """Replaces in-memory product ledger with real user inventory items from client app."""
        if not custom_products:
            return
        new_dict = {}
        for item in custom_products:
            barcode = str(item.get("barcode", "") or item.get("sku", "") or item.get("id", "") or item.get("name", "")).strip()
            if not barcode:
                continue
            new_dict[barcode] = {
                "barcode": barcode,
                "name": item.get("name", "Unnamed Product"),
                "stock": int(item.get("stock", item.get("quantity", 0))),
                "min_threshold": int(item.get("min_threshold", item.get("lowStockThreshold", 10))),
                "category": item.get("category", item.get("categoryName", "General")),
                "cost_price": float(item.get("cost_price", item.get("costPrice", 0.0))),
                "selling_price": float(item.get("selling_price", item.get("price", item.get("sellingPrice", 0.0)))),
                "sales_velocity": int(item.get("sales_velocity", 0)),
                "lead_time_days": int(item.get("lead_time_days", 3)),
                "location": item.get("location", "Store Main")
            }
        if new_dict:
            self.products = new_dict
            self._save()

    def get_all_products(self) -> List[Dict[str, Any]]:
        return list(self.products.values())

    def get_product(self, barcode: str) -> Optional[Dict[str, Any]]:
        return self.products.get(barcode)

    def find_product_by_name(self, name_query: str) -> Optional[Dict[str, Any]]:
        q = name_query.lower()
        for p in self.products.values():
            if q in p["name"].lower() or p["name"].lower() in q:
                return p
        return None

    def upsert_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        barcode = product_data.get("barcode")
        if not barcode:
            raise ValueError("Barcode is required for upserting a product.")
        
        existing = self.products.get(barcode, {})
        existing.update(product_data)
        self.products[barcode] = existing
        
        self.action_ledger.append({
            "action": "upsert_product",
            "barcode": barcode,
            "timestamp": datetime.now().isoformat(),
            "details": product_data
        })
        self._save()
        return existing

    def update_stock(self, barcode: str, qty_change: int, reason: str = "Manual Adjustment") -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
            if not product:
                return {"success": False, "error": f"Product with barcode/name '{barcode}' not found in DB."}

        new_stock = product["stock"] + qty_change
        if new_stock < 0:
            return {
                "success": False,
                "error": f"Insufficient stock for {product['name']}. Current stock: {product['stock']}, requested deduction: {abs(qty_change)}."
            }

        old_stock = product["stock"]
        product["stock"] = new_stock
        
        log_entry = {
            "action": "update_stock",
            "barcode": product["barcode"],
            "product_name": product["name"],
            "old_stock": old_stock,
            "new_stock": new_stock,
            "qty_change": qty_change,
            "reason": reason,
            "timestamp": datetime.now().isoformat()
        }
        self.action_ledger.append(log_entry)
        self._save()
        
        return {
            "success": True,
            "product": product,
            "old_stock": old_stock,
            "new_stock": new_stock,
            "action_logged": log_entry
        }

    def create_purchase_order(self, barcode: str, reorder_qty: int, supplier: str = "Default Supplier") -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
            if not product:
                return {"success": False, "error": f"Product '{barcode}' not found."}

        po_id = f"PO-{int(datetime.now().timestamp())}"
        total_cost = reorder_qty * product.get("cost_price", 0.0)
        
        log_entry = {
            "action": "create_purchase_order",
            "po_id": po_id,
            "barcode": product["barcode"],
            "product_name": product["name"],
            "reorder_qty": reorder_qty,
            "supplier": supplier,
            "unit_cost": product.get("cost_price", 0.0),
            "total_cost": total_cost,
            "status": "DRAFT",
            "timestamp": datetime.now().isoformat()
        }
        self.action_ledger.append(log_entry)
        self._save()

        return {
            "success": True,
            "po_id": po_id,
            "product": product,
            "reorder_qty": reorder_qty,
            "supplier": supplier,
            "total_cost": total_cost,
            "action_logged": log_entry
        }

    def transfer_stock(self, barcode: str, from_loc: str, to_loc: str, qty: int) -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
            if not product:
                return {"success": False, "error": f"Product '{barcode}' not found."}

        if product["stock"] < qty:
            return {"success": False, "error": f"Cannot transfer {qty} units. Only {product['stock']} available."}

        product["location"] = to_loc
        log_entry = {
            "action": "transfer_stock",
            "barcode": product["barcode"],
            "product_name": product["name"],
            "from_location": from_loc,
            "to_location": to_loc,
            "qty": qty,
            "timestamp": datetime.now().isoformat()
        }
        self.action_ledger.append(log_entry)
        self._save()

        return {
            "success": True,
            "product": product,
            "from_location": from_loc,
            "to_location": to_loc,
            "qty": qty,
            "action_logged": log_entry
        }

    def audit_inventory(self, barcode: str, actual_stock: int, notes: str = "Physical Audit") -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
            if not product:
                return {"success": False, "error": f"Product '{barcode}' not found."}

        discrepancy = actual_stock - product["stock"]
        old_stock = product["stock"]
        product["stock"] = actual_stock

        log_entry = {
            "action": "audit_inventory",
            "barcode": product["barcode"],
            "product_name": product["name"],
            "old_stock": old_stock,
            "actual_stock": actual_stock,
            "discrepancy": discrepancy,
            "notes": notes,
            "timestamp": datetime.now().isoformat()
        }
        self.action_ledger.append(log_entry)
        self._save()

        return {
            "success": True,
            "product": product,
            "old_stock": old_stock,
            "actual_stock": actual_stock,
            "discrepancy": discrepancy,
            "action_logged": log_entry
        }

    def set_min_threshold(self, barcode: str, new_threshold: int) -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
            if not product:
                return {"success": False, "error": f"Product '{barcode}' not found."}

        old_t = product.get("min_threshold", 10)
        product["min_threshold"] = new_threshold

        log_entry = {
            "action": "set_min_threshold",
            "barcode": product["barcode"],
            "product_name": product["name"],
            "old_threshold": old_t,
            "new_threshold": new_threshold,
            "timestamp": datetime.now().isoformat()
        }
        self.action_ledger.append(log_entry)
        self._save()

        return {
            "success": True,
            "product": product,
            "old_threshold": old_t,
            "new_threshold": new_threshold,
            "action_logged": log_entry
        }

    def get_analytics_summary(self) -> Dict[str, Any]:
        all_prods = self.get_all_products()
        total_items = len(all_prods)
        low_stock_items = [p for p in all_prods if p["stock"] <= p.get("min_threshold", 10) and p["stock"] > 0]
        out_of_stock_items = [p for p in all_prods if p["stock"] == 0]
        total_inventory_value = sum(p["stock"] * p.get("selling_price", 0.0) for p in all_prods)
        total_cost_value = sum(p["stock"] * p.get("cost_price", 0.0) for p in all_prods)

        high_velocity = sorted(all_prods, key=lambda x: x.get("sales_velocity", 0), reverse=True)

        return {
            "total_products": total_items,
            "low_stock_count": len(low_stock_items),
            "out_of_stock_count": len(out_of_stock_items),
            "low_stock_items": low_stock_items,
            "out_of_stock_items": out_of_stock_items,
            "total_inventory_value": round(total_inventory_value, 2),
            "total_cost_value": round(total_cost_value, 2),
            "top_velocity_items": high_velocity[:3]
        }

    def run_autopilot_scan(self) -> List[Dict[str, Any]]:
        """
        Proactively scans all products to find items requiring reorder recommendations.
        Formula: Lead time demand = (weekly_sales_velocity / 7) * lead_time_days
        Suggested reorder = max(min_threshold * 2, lead_time_demand * 2) - current_stock
        """
        all_prods = self.get_all_products()
        recommendations = []
        for p in all_prods:
            stock = p.get("stock", 0)
            threshold = p.get("min_threshold", 10)
            velocity = p.get("sales_velocity", 0)
            lead_days = p.get("lead_time_days", 3)

            daily_velocity = velocity / 7.0
            lead_time_demand = daily_velocity * lead_days

            if stock <= threshold or stock <= lead_time_demand:
                target_stock = max(threshold * 2, int(lead_time_demand * 2))
                suggested_reorder = max(10, target_stock - stock)
                recommendations.append({
                    "barcode": p["barcode"],
                    "product_name": p["name"],
                    "current_stock": stock,
                    "min_threshold": threshold,
                    "weekly_sales_velocity": velocity,
                    "lead_time_days": lead_days,
                    "suggested_reorder_qty": suggested_reorder,
                    "urgency": "HIGH" if stock == 0 else "MEDIUM"
                })
        return recommendations

db_instance = InventoryDB()
