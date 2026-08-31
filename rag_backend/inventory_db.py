import json
import os
import re
from typing import Dict, List, Optional, Any
from datetime import datetime


DB_FILE = os.path.join(os.path.dirname(__file__), "inventory_db.json")

# Initialize Firebase Admin SDK for Cloud Run / Firestore native sync
db_firestore = None
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={'projectId': 'stockmanagement-27af8'})
    db_firestore = firestore.client()
    print("[Firestore Native Client] Connected to project 'stockmanagement-27af8'")
except Exception as e:
    db_firestore = None
    print(f"[Firestore Native Client Note] Initialized in offline/local mode: {e}")

class InventoryDB:
    def __init__(self, db_path: str = DB_FILE):
        self.db_path = db_path
        self.company_data: Dict[str, Dict[str, Any]] = {}
        self._load()

    def _sync_from_firestore(self, company_id: str):
        if not db_firestore or not company_id or company_id == "default":
            return
        try:
            docs = db_firestore.collection("companies").document(company_id).collection("products").limit(500).stream()
            co = self._get_company_raw(company_id)
            fetched_products = {}
            for doc in docs:
                data = doc.to_dict() or {}
                doc_id = doc.id
                barcode = str(data.get("barcode") or doc_id).strip()
                name = data.get("name") or "Unknown Product"
                stock = int(data.get("quantity", 0))
                min_thresh = int(data.get("lowStockThreshold", 10))
                cat = data.get("categoryName") or data.get("category") or "General"
                cost = float(data.get("costPrice", 0.0))
                price = float(data.get("sellingPrice", 0.0))
                velocity = float(data.get("salesVelocity", 0.0))
                lead_time = int(data.get("leadTimeDays", 3))
                loc_quantities = {
                    str(k): int(v or 0)
                    for k, v in (data.get("locationQuantities") or {}).items()
                }
                loc = (
                    max(loc_quantities, key=lambda k: loc_quantities[k])
                    if loc_quantities
                    else data.get("location", "Store Front")
                )

                fetched_products[barcode] = {
                    "id": doc_id,
                    "barcode": barcode,
                    "name": name,
                    "stock": stock,
                    "min_threshold": min_thresh,
                    "category": cat,
                    "cost_price": cost,
                    "selling_price": price,
                    "sales_velocity": velocity,
                    "lead_time_days": lead_time,
                    "location": loc,
                    "location_quantities": loc_quantities,
                    "held_quantity": int(data.get("heldQuantity", 0) or 0),
                    "last_updated_timestamp": datetime.now().isoformat()
                }

            if fetched_products:
                co["products"] = fetched_products
        except Exception as e:
            print(f"[Firestore Sync Error] Failed to fetch products for company '{company_id}': {e}")

    def _sync_to_firestore(self, company_id: str, action_type: str, product_data: Dict[str, Any], qty_change: int = 0, from_loc: str = None, to_loc: str = None):
        if not db_firestore or not company_id:
            return
        try:
            from firebase_admin import firestore
            doc_id = str(product_data.get("id") or product_data.get("barcode") or "").strip()
            if not doc_id:
                return
            prod_ref = db_firestore.collection("companies").document(company_id).collection("products").document(doc_id)
            
            update_data = {
                "name": product_data.get("name"),
                "barcode": product_data.get("barcode"),
                "lowStockThreshold": product_data.get("min_threshold"),
                "categoryName": product_data.get("category"),
                "costPrice": product_data.get("cost_price"),
                "sellingPrice": product_data.get("selling_price"),
                "updatedAt": datetime.now()
            }
            loc = product_data.get("location", "Store Front")

            if action_type in ["update_stock", "voice_add", "voice_deduct"] and qty_change != 0:
                update_data["quantity"] = firestore.Increment(qty_change)
                update_data[f"locationQuantities.{loc}"] = firestore.Increment(qty_change)
                update_data["location"] = loc
            elif action_type == "transfer_stock" and from_loc and to_loc:
                update_data[f"locationQuantities.{from_loc}"] = firestore.Increment(-qty_change)
                update_data[f"locationQuantities.{to_loc}"] = firestore.Increment(qty_change)
                update_data["location"] = to_loc
            elif action_type == "audit_inventory" or (action_type == "replace_user_inventory"):
                # Complete override for audit and generic replacements
                update_data["quantity"] = product_data.get("stock")
                update_data[f"locationQuantities.{loc}"] = product_data.get("stock")
                update_data["location"] = loc
            
            prod_ref.set(update_data, merge=True)

            flutter_type = "adjustment"
            if action_type == "create_purchase_order" or "add" in action_type:
                flutter_type = "stock_in"
            elif "deduct" in action_type:
                flutter_type = "stock_out"
            elif action_type == "transfer_stock":
                flutter_type = "transfer"
            
            tx_ref = db_firestore.collection("companies").document(company_id).collection("transactions").document()
            tx_ref.set({
                "type": flutter_type,
                "productId": doc_id,
                "productName": product_data.get("name"),
                "quantity": abs(qty_change) if qty_change else product_data.get("stock"),
                "location": to_loc if action_type == "transfer_stock" else loc,
                # `date`, `userId` and `userName` are the field names
                # StockTransactionModel.fromMap reads. Writing `timestamp` /
                # `performedBy` meant AI movements showed the wrong date, no
                # attribution, and polluted the ledger the fact layer derives
                # demand from.
                "date": datetime.now(),
                "userId": "ai_agent",
                "userName": "Ask AI",
                "reason": product_data.get("_reason", "AI action"),
                "vendorId": "",
                "vendorName": "",
            })
            print(f"[Firestore Sync Success] Updated product '{doc_id}' for company '{company_id}'")
        except Exception as e:
            print(f"[Firestore Write Error] Sync failed for company '{company_id}': {e}")


    def _get_company_raw(self, company_id: Optional[str] = "default") -> Dict[str, Any]:
        cid = (company_id or "default").strip()
        if not cid:
            cid = "default"
        if cid not in self.company_data:
            self.company_data[cid] = {
                "products": {},
                "action_ledger": []
            }
        return self.company_data[cid]

    def _get_company(self, company_id: Optional[str] = "default") -> Dict[str, Any]:
        cid = (company_id or "default").strip()
        if not cid:
            cid = "default"
        if cid not in self.company_data:
            self.company_data[cid] = {
                "products": {},
                "action_ledger": []
            }
            self._sync_from_firestore(cid)
        return self.company_data[cid]


    @property
    def products(self) -> Dict[str, Dict[str, Any]]:
        return self._get_company("default")["products"]

    @products.setter
    def products(self, value: Dict[str, Dict[str, Any]]):
        self._get_company("default")["products"] = value

    @property
    def action_ledger(self) -> List[Dict[str, Any]]:
        return self._get_company("default")["action_ledger"]

    @action_ledger.setter
    def action_ledger(self, value: List[Dict[str, Any]]):
        self._get_company("default")["action_ledger"] = value

    def _load(self):
        if os.path.exists(self.db_path):
            try:
                with open(self.db_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if "company_data" in data and isinstance(data["company_data"], dict):
                        self.company_data = data["company_data"]
                    else:
                        prods = data.get("products", {})
                        ledger = data.get("action_ledger", [])
                        self.company_data = {
                            "default": {
                                "products": prods,
                                "action_ledger": ledger
                            }
                        }
            except Exception as e:
                print(f"Error loading inventory DB: {e}")
    def _save(self):
        try:
            temp_path = self.db_path + ".tmp"
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump({
                    "company_data": self.company_data,
                    "products": self.products,
                    "action_ledger": self.action_ledger
                }, f, indent=2)
            os.replace(temp_path, self.db_path)
        except Exception as e:
            print(f"Error saving inventory DB: {e}")

    def replace_user_inventory(self, custom_products: List[Dict[str, Any]], company_id: str = "default"):
        """Replaces in-memory product ledger for a specific company with real user inventory items from client app while preserving backend updates."""
        if not custom_products:
            return
        company = self._get_company(company_id)
        current_prods = company["products"]
        new_dict = {}
        for item in custom_products:
            barcode = str(item.get("barcode", "") or item.get("sku", "") or item.get("id", "") or item.get("name", "")).strip()
            if not barcode:
                continue
            
            # The client (and behind it, Firestore) is the source of truth.
            # This used to keep the backend's own stock value whenever it had
            # ever written to the product, which made the AI's view diverge
            # permanently from the app's.
            stock_val = int(item.get("stock", item.get("quantity", 0)))

            new_dict[barcode] = {
                "id": str(item.get("id", "")).strip() or barcode,
                "barcode": barcode,
                "name": item.get("name", "Unnamed Product"),
                "stock": stock_val,
                "min_threshold": int(item.get("min_threshold", item.get("lowStockThreshold", 10))),
                "category": item.get("category", item.get("categoryName", "General")),
                "cost_price": float(item.get("cost_price", item.get("costPrice", 0.0))),
                "selling_price": float(item.get("selling_price", item.get("price", item.get("sellingPrice", 0.0)))),
                "sales_velocity": float(item.get("sales_velocity", 0.0)),
                "lead_time_days": int(item.get("lead_time_days", 3)),
                "held_quantity": int(item.get("held_quantity", item.get("heldQuantity", 0))),
                "location": item.get("location", "Store Main"),
            }
                
        if new_dict:
            company["products"] = new_dict
            self._save()
            self._invalidate(company_id)

    def get_all_products(self, company_id: str = "default", limit: int = 10000, offset: int = 0) -> List[Dict[str, Any]]:
        prods = list(self._get_company(company_id)["products"].values())
        return prods[offset:offset + limit]

    def get_product(self, barcode: str, company_id: str = "default") -> Optional[Dict[str, Any]]:
        return self._get_company(company_id)["products"].get(barcode)

    def find_product_by_name(self, name_query: str, company_id: str = "default") -> Optional[Dict[str, Any]]:
        q = name_query.lower()
        for p in self.get_all_products(company_id):
            if q in p["name"].lower() or p["name"].lower() in q:
                return p
        return None

    def upsert_product(self, product_data: Dict[str, Any], company_id: str = "default") -> Dict[str, Any]:
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


    def update_stock(self, barcode: str, qty_change: int, reason: str = "Manual Adjustment", company_id: str = "default") -> Dict[str, Any]:
        company = self._get_company(company_id)
        product = company["products"].get(barcode)
        if not product:
            product = self.find_product_by_name(barcode, company_id=company_id)
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
        company["products"][target_barcode] = product
        
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
        company["action_ledger"].append(log_entry)
        self._save()
        self._invalidate(company_id)
        
        sync_action = "update_stock"
        if "add" in reason.lower():
            sync_action = "voice_add"
        elif "deduct" in reason.lower() or "damage" in reason.lower():
            sync_action = "voice_deduct"
            
        self._sync_to_firestore(company_id, sync_action, product, qty_change=qty_change)
        
        return {
            "success": True,
            "product": product,
            "old_stock": old_stock,
            "new_stock": new_stock,
            "qty_change": qty_change,
            "action_logged": log_entry
        }


    def create_purchase_order(self, barcode: str, reorder_qty: int, supplier: str = "Default Supplier", company_id: str = "default") -> Dict[str, Any]:
        company = self._get_company(company_id)
        product = company["products"].get(barcode)
        if not product:
            product = self.find_product_by_name(barcode, company_id=company_id)
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
        company["action_ledger"].append(log_entry)
        self._save()
        self._invalidate(company_id)
        self._sync_to_firestore(company_id, "create_purchase_order", product)

        return {
            "success": True,
            "po_id": po_id,
            "product": product,
            "reorder_qty": reorder_qty,
            "supplier": supplier,
            "total_cost": total_cost,
            "action_logged": log_entry
        }

    def transfer_stock(self, barcode: str, from_loc: str, to_loc: str, qty: int, company_id: str = "default") -> Dict[str, Any]:
        company = self._get_company(company_id)
        product = company["products"].get(barcode)
        if not product:
            product = self.find_product_by_name(barcode, company_id=company_id)
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
        company["action_ledger"].append(log_entry)
        self._save()
        self._invalidate(company_id)
        self._sync_to_firestore(company_id, "transfer_stock", product, qty_change=qty, from_loc=from_loc, to_loc=to_loc)

        return {
            "success": True,
            "product": product,
            "from_location": from_loc,
            "to_location": to_loc,
            "qty": qty,
            "action_logged": log_entry
        }

    def audit_inventory(self, barcode: str, actual_stock: int, notes: str = "Physical Audit", company_id: str = "default") -> Dict[str, Any]:
        company = self._get_company(company_id)
        product = company["products"].get(barcode)
        if not product:
            product = self.find_product_by_name(barcode, company_id=company_id)
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
        company["action_ledger"].append(log_entry)
        self._save()
        self._invalidate(company_id)
        self._sync_to_firestore(company_id, "audit_inventory", product, qty_change=discrepancy)


        return {
            "success": True,
            "product": product,
            "old_stock": old_stock,
            "actual_stock": actual_stock,
            "discrepancy": discrepancy,
            "action_logged": log_entry
        }

    def set_min_threshold(self, barcode: str, new_threshold: int, company_id: str = "default") -> Dict[str, Any]:
        company = self._get_company(company_id)
        product = company["products"].get(barcode)
        if not product:
            product = self.find_product_by_name(barcode, company_id=company_id)

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
        company["action_ledger"].append(log_entry)
        self._save()
        self._invalidate(company_id)

        return {
            "success": True,
            "product": product,
            "old_threshold": old_t,
            "new_threshold": new_threshold,
            "action_logged": log_entry
        }

    def get_analytics_summary(self, company_id: str = "default") -> Dict[str, Any]:
        all_prods = self.get_all_products(company_id=company_id)
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

    # run_autopilot_scan / detect_inventory_anomalies /
    # get_predictive_demand_forecast / get_cross_location_balance_suggestions
    # lived here. They computed on a `sales_velocity` field the app never
    # writes (so always 0.0), and disagreed with predictive_ml about whether
    # that field was weekly or daily. The endpoints that used them now read
    # `facts.py`, which derives real daily burn rates from the transaction
    # ledger. See BACKEND_ARCHITECTURE.md section 2.

    def process_visual_audit_photo(self, detected_items: List[Dict[str, Any]], company_id: str = "default") -> Dict[str, Any]:
        """
        Processes visual stock detection counts against expected database values.
        detected_items format: [{"name": "Fresh Apples", "count": 12}, ...]
        """
        audit_results = []
        for item in detected_items:
            name_query = item.get("name", "")
            counted_qty = item.get("count", 0)
            product = self.find_product_by_name(name_query, company_id=company_id)

            if product:
                disc = counted_qty - product["stock"]
                audit_res = self.audit_inventory(product["barcode"], counted_qty, f"Visual AI Camera Audit: Counted {counted_qty}", company_id=company_id)
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

    @staticmethod
    def _sanitize_speech_text(speech_text: str) -> str:
        """Cleans and deduplicates spoken speech text and maps spoken numbers."""
        if not speech_text:
            return ""
        
        num_map = {
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
            "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
            "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
            "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
            "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
            "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
            "eighty": "80", "ninety": "90", "hundred": "100"
        }
        
        words = re.findall(r'[a-zA-Z0-9]+', speech_text.lower())
        if not words:
            return ""
            
        cleaned_words = []
        for w in words:
            mapped_word = num_map.get(w, w)
            if cleaned_words and cleaned_words[-1] == mapped_word:
                continue
            cleaned_words.append(mapped_word)
            
        return " ".join(cleaned_words)

    def process_voice_command(self, speech_text: str, company_id: str = "default") -> Dict[str, Any]:
        """
        Parses spoken natural language commands (e.g. 'Deduct 15 units of Fresh Apples damaged')
        and executes atomic stock mutations with audio confirmation feedback.
        """
        text_lower = self._sanitize_speech_text(speech_text)
        all_prods = self.get_all_products(company_id=company_id)
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
            res = self.audit_inventory(target_prod["barcode"], qty, f"Voice AI Audit: {speech_text}", company_id=company_id)
            if res.get("success", False):
                audio_text = f"Voice Audit Completed: {target_prod['name']} stock updated to {qty} units."
                status = "success"
            else:
                audio_text = f"Could not audit {target_prod['name']}: {res.get('error', 'Audit failed')}."
                status = "error"
            return {
                "status": status,
                "action": "voice_audit",
                "audio_response_text": audio_text,
                "execution_result": res
            }
        elif is_deduct and target_prod:
            res = self.update_stock(target_prod["barcode"], -qty, f"Voice AI Deduction: {speech_text}", company_id=company_id)
            if res.get("success", False):
                new_stk = res.get("new_stock", res.get("product", {}).get("stock", 0))
                audio_text = f"Updated: Deducted {qty} units of {target_prod['name']}. Remaining stock: {new_stk}."
                status = "success"
            else:
                audio_text = f"Could not deduct {qty} units of {target_prod['name']}: {res.get('error', 'Insufficient stock')}."
                status = "error"
            return {
                "status": status,
                "action": "voice_deduct",
                "audio_response_text": audio_text,
                "execution_result": res
            }
        elif (is_add or not is_deduct) and target_prod:
            res = self.update_stock(target_prod["barcode"], qty, f"Voice AI Addition: {speech_text}", company_id=company_id)
            if res.get("success", False):
                new_stk = res.get("new_stock", res.get("product", {}).get("stock", 0))
                audio_text = f"Updated: Added {qty} units to {target_prod['name']}. Total stock: {new_stk}."
                status = "success"
            else:
                audio_text = f"Could not add {qty} units to {target_prod['name']}: {res.get('error', 'Update failed')}."
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

    def _invalidate(self, company_id: str) -> None:
        """Rotate the cached fact snapshot after a local write."""
        try:
            from facts import fact_store

            fact_store.bump(company_id)
        except Exception:
            pass


db_instance = InventoryDB()


