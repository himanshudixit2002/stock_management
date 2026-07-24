import json
import os
import re
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
        """Replaces in-memory product ledger with real user inventory items from client app while preserving backend updates."""
        if not custom_products:
            return
        new_dict = {}
        for item in custom_products:
            barcode = str(item.get("barcode", "") or item.get("sku", "") or item.get("id", "") or item.get("name", "")).strip()
            if not barcode:
                continue
            
            existing = self.products.get(barcode)
            stock_val = int(item.get("stock", item.get("quantity", 0)))
            
            # If item was updated on the backend, preserve the backend's updated stock value
            if existing and "last_updated_timestamp" in existing:
                stock_val = existing["stock"]

            new_dict[barcode] = {
                "barcode": barcode,
                "name": item.get("name", "Unnamed Product"),
                "stock": stock_val,
                "min_threshold": int(item.get("min_threshold", item.get("lowStockThreshold", 10))),
                "category": item.get("category", item.get("categoryName", "General")),
                "cost_price": float(item.get("cost_price", item.get("costPrice", 0.0))),
                "selling_price": float(item.get("selling_price", item.get("price", item.get("sellingPrice", 0.0)))),
                "sales_velocity": int(item.get("sales_velocity", 0)),
                "lead_time_days": int(item.get("lead_time_days", 3)),
                "location": item.get("location", "Store Main")
            }
            if existing and "last_updated_timestamp" in existing:
                new_dict[barcode]["last_updated_timestamp"] = existing["last_updated_timestamp"]
                
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
        existing["last_updated_timestamp"] = datetime.now().isoformat()
        self.products[barcode] = existing
        
        self.action_ledger.append({
            "action": "upsert_product",
            "barcode": barcode,
            "timestamp": datetime.now().isoformat(),
            "details": product_data
        })
        self._save()
        return existing

    def add_action_log(self, action_type: str, details: Dict[str, Any], user: str = "AI_AGENT"):
        log_entry = {
            "action": action_type,
            "user": user,
            "timestamp": datetime.now().isoformat(),
            "details": details
        }
        self.action_ledger.append(log_entry)
        self._save()
        return log_entry


    def update_stock(self, barcode: str, qty_change: int, reason: str = "Manual Adjustment") -> Dict[str, Any]:
        product = self.products.get(barcode)
        if not product:
            product = self.find_product_by_name(barcode)
        if not product:
            return {"success": False, "error": f"Product not found: {barcode}"}
        
        target_barcode = product["barcode"]
        old_stock = int(product.get("stock", 0))
        new_stock = max(0, old_stock + qty_change)

        if (old_stock + qty_change) < 0:
            return {
                "success": False,
                "error": f"Insufficient stock for {product['name']}. Current stock: {old_stock}, requested deduction: {abs(qty_change)}."
            }

        product["stock"] = new_stock
        product["last_updated_timestamp"] = datetime.now().isoformat()
        self.products[target_barcode] = product
        
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
            "qty_change": qty_change,
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

    def detect_inventory_anomalies(self) -> List[Dict[str, Any]]:
        """
        Scans stock ledger and inventory state for shrinkages, sudden large drops, or unauthorized stockouts.
        """
        anomalies = []
        all_prods = self.get_all_products()

        # 1. Check ledger for suspicious high-volume deductions or negative adjustments
        for log in reversed(self.action_ledger[-50:]):
            action = log.get("action")
            qty_change = log.get("qty_change", 0)
            disc = log.get("discrepancy", 0)

            if action == "update_stock" and qty_change < -20:
                anomalies.append({
                    "type": "HIGH_SHRINKAGE_SPIKE",
                    "product_name": log.get("product_name"),
                    "barcode": log.get("barcode"),
                    "severity": "CRITICAL",
                    "description": f"Unusual sudden deduction of {abs(qty_change)} units logged.",
                    "timestamp": log.get("timestamp")
                })
            elif action == "audit_inventory" and abs(disc) > 10:
                anomalies.append({
                    "type": "LARGE_AUDIT_DISCREPANCY",
                    "product_name": log.get("product_name"),
                    "barcode": log.get("barcode"),
                    "severity": "HIGH",
                    "description": f"Physical count discrepancy of {disc:+d} units detected.",
                    "timestamp": log.get("timestamp")
                })

        # 2. Check current stock state for anomalous zero-stock on high velocity items
        for p in all_prods:
            if p.get("stock", 0) == 0 and p.get("sales_velocity", 0) > 30:
                anomalies.append({
                    "type": "UNEXPECTED_HIGH_VELOCITY_STOCKOUT",
                    "product_name": p["name"],
                    "barcode": p["barcode"],
                    "severity": "CRITICAL",
                    "description": f"High velocity item ({p['sales_velocity']} units/wk) is completely out of stock!",
                    "timestamp": datetime.now().isoformat()
                })

        return anomalies

    def get_predictive_demand_forecast(self) -> List[Dict[str, Any]]:
        """
        Calculates 30-day time-series demand forecasts, statistical safety stock, and projected stockout dates.
        """
        try:
            from predictive_ml import predict_30day_demand_forecast, calculate_statistical_safety_stock, calculate_stockout_risk_timeline
        except ImportError:
            from .predictive_ml import predict_30day_demand_forecast, calculate_statistical_safety_stock, calculate_stockout_risk_timeline

        forecasts = []
        all_prods = self.get_all_products()

        for p in all_prods:
            stock = p.get("stock", 0)
            velocity = p.get("sales_velocity", 1.0)
            lead_days = p.get("lead_time_days", 3)

            forecast_curve = predict_30day_demand_forecast(p, days=30)
            risk_info = calculate_stockout_risk_timeline(p)
            stat_safety_stock = calculate_statistical_safety_stock(velocity, lead_days)

            total_30d_demand = sum(f["projected_daily_demand"] for f in forecast_curve)

            forecasts.append({
                "barcode": p["barcode"],
                "product_name": p["name"],
                "current_stock": stock,
                "daily_sales_rate": round(velocity, 2),
                "statistical_safety_stock": stat_safety_stock,
                "projected_30d_demand": round(total_30d_demand, 1),
                "days_until_stockout": risk_info["days_until_stockout"],
                "risk_level": risk_info["risk_level"],
                "revenue_at_risk": risk_info["revenue_at_risk"],
                "recommendation": risk_info["recommendation"],
                "daily_forecast_trajectory": forecast_curve[:7]  # First 7 days preview
            })

        return sorted(forecasts, key=lambda x: x["days_until_stockout"])


    def get_cross_location_balance_suggestions(self) -> List[Dict[str, Any]]:
        """
        Identifies overstocked locations vs understocked locations to create instant stock transfer recommendations.
        """
        all_prods = self.get_all_products()
        transfers = []

        # Find items with high stock in warehouse vs low stock in store front
        for p in all_prods:
            loc = p.get("location", "Store Front")
            stock = p.get("stock", 0)
            th = p.get("min_threshold", 10)

            if "Warehouse" in loc and stock > (th * 3):
                # Warehouse has excess stock
                transfers.append({
                    "barcode": p["barcode"],
                    "product_name": p["name"],
                    "from_location": loc,
                    "to_location": "Store Front - Main Shelf",
                    "suggested_transfer_qty": int(stock * 0.4),
                    "reason": "Balance excess warehouse stock to store front shelf"
                })

        return transfers

    def process_visual_audit_photo(self, detected_items: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Processes visual stock detection counts against expected database values.
        detected_items format: [{"name": "Fresh Apples", "count": 12}, ...]
        """
        audit_results = []
        for item in detected_items:
            name_query = item.get("name", "")
            counted_qty = item.get("count", 0)
            product = self.find_product_by_name(name_query)

            if product:
                disc = counted_qty - product["stock"]
                audit_res = self.audit_inventory(product["barcode"], counted_qty, f"Visual AI Camera Audit: Counted {counted_qty}")
                audit_results.append({
                    "product_name": product["name"],
                    "barcode": product["barcode"],
                    "expected_stock": audit_res.get("old_stock"),
                    "visual_counted_stock": counted_qty,
                    "discrepancy": disc,
                    "success": audit_res.get("success")
                })
            else:
                audit_results.append({
                    "product_name": name_query,
                    "error": "Product not found in catalog"
                })

        return {
            "timestamp": datetime.now().isoformat(),
            "audited_items_count": len(audit_results),
            "results": audit_results
        }

    def process_voice_command(self, speech_text: str) -> Dict[str, Any]:
        """
        Parses spoken natural language commands (e.g. 'Deduct 15 units of Fresh Apples damaged')
        and executes atomic stock mutations with audio confirmation feedback.
        """
        text_lower = speech_text.lower().strip()
        all_prods = self.get_all_products()
        stop_words = {"a", "an", "the", "in", "of", "on", "units", "unit", "to", "for", "from", "at", "by", "with", "add", "deduct", "remove", "damaged", "sold", "received", "restock", "count", "audit", "plus", "minus"}
        
        # Match target product by best keyword/substring score
        target_prod = None
        best_score = 0

        for p in all_prods:
            p_name = p["name"].lower()
            p_barcode = p["barcode"].lower()
            score = 0
            
            if p_name in text_lower:
                score += 100
            if p_barcode and p_barcode in text_lower:
                score += 150
                
            keywords = [w for w in p_name.split() if w not in stop_words and len(w) > 1]
            matched_kw = sum(1 for kw in keywords if kw in text_lower)
            if matched_kw > 0:
                score += (matched_kw * 10)

            if score > best_score:
                best_score = score
                target_prod = p
                
        if not target_prod or best_score < 10:
            return {
                "status": "error",
                "error": "Product not found",
                "audio_response_text": f"Could not find any inventory item matching '{speech_text}'."
            }


        # Extract numerical quantity using regex
        qty_matches = re.findall(r'\b\d+\b', text_lower)
        qty = int(qty_matches[0]) if qty_matches else 1

        is_deduct = any(w in text_lower for w in ["deduct", "remove", "damaged", "sold", "subtract", "minus", "reduce"])
        is_add = any(w in text_lower for w in ["add", "received", "restock", "increment", "plus"])
        is_audit = any(w in text_lower for w in ["audit", "count", "physical"])

        if is_audit and target_prod:
            res = self.audit_inventory(target_prod["barcode"], qty, f"Voice AI Audit: {speech_text}")
            audio_text = f"Voice Audit Completed: {target_prod['name']} stock updated to {qty} units."
            return {
                "status": "success",
                "action": "voice_audit",
                "audio_response_text": audio_text,
                "execution_result": res
            }
        elif is_deduct and target_prod:
            res = self.update_stock(target_prod["barcode"], -qty, f"Voice AI Deduction: {speech_text}")
            audio_text = f"Updated: Deducted {qty} units of {target_prod['name']}. Remaining stock: {res['product']['stock']}."
            return {
                "status": "success",
                "action": "voice_deduct",
                "audio_response_text": audio_text,
                "execution_result": res
            }
        elif (is_add or not is_deduct) and target_prod:
            res = self.update_stock(target_prod["barcode"], qty, f"Voice AI Addition: {speech_text}")
            audio_text = f"Updated: Added {qty} units to {target_prod['name']}. Total stock: {res['product']['stock']}."
            return {
                "status": "success",
                "action": "voice_add",
                "audio_response_text": audio_text,
                "execution_result": res
            }

        return {
            "status": "ERROR",
            "audio_response_text": f"Could not match product in speech command: '{speech_text}'. Please specify product name.",
            "execution_result": None
        }

db_instance = InventoryDB()


