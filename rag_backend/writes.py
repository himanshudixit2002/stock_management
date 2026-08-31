"""
Mutation layer — every write the agent can perform.

Two things were wrong with the old write path:

1. It looked products up in a local JSON store keyed by barcode, while the app
   keys everything by Firestore document id. When the local copy was stale or
   missing, writes landed on the wrong SKU or silently no-op'd.
2. It wrote transaction documents with `timestamp` / `performedBy`, but the app
   reads `date` / `userId` / `userName`. AI-created movements therefore showed
   up with the wrong date and no attribution — and corrupted the very ledger the
   fact layer now derives demand from.

Writes here go straight to Firestore against the real document id carried on a
ProductFact, inside a transaction so concurrent updates cannot lose each other
or drive stock negative.
"""

from __future__ import annotations
import os

from datetime import datetime, timezone
from typing import Any, Dict, Optional

from facts import ProductFact, fact_store

AI_ACTOR_ID = "ai_agent"
AI_ACTOR_NAME = "Ask AI"


def _client():
    try:
        from inventory_db import db_firestore

        return db_firestore
    except Exception:
        return None


def _company_ref(client, company_id: str):
    return client.collection("companies").document(company_id)


def _log_ledger(company_id: str, entry: Dict[str, Any]) -> None:
    """Keep the local action ledger in step so the audit-log answer still works."""
    try:
        from inventory_db import db_instance

        entry = dict(entry)
        entry.setdefault("timestamp", datetime.now(timezone.utc).isoformat())
        db_instance._get_company(company_id)["action_ledger"].append(entry)
        db_instance._save()
    except Exception as exc:
        print(f"[writes] ledger append failed: {exc}")


def _write_transaction(
    client,
    company_id: str,
    product: ProductFact,
    tx_type: str,
    quantity: int,
    reason: str,
    location: str = "",
    vendor_id: str = "",
    vendor_name: str = "",
) -> None:
    """Write a transaction doc in exactly the shape StockTransactionModel reads."""
    try:
        ref = _company_ref(client, company_id).collection("transactions").document()
        ref.set(
            {
                "productId": product.id,
                "productName": product.name,
                "type": tx_type,
                "quantity": abs(int(quantity)),
                "location": location or product.location or "",
                "reason": reason,
                "userId": AI_ACTOR_ID,
                "userName": AI_ACTOR_NAME,
                "date": datetime.now(timezone.utc),
                "vendorId": vendor_id or product.vendor_id or "",
                "vendorName": vendor_name or product.vendor_name or "",
            }
        )
    except Exception as exc:
        print(f"[writes] transaction write failed: {exc}")


def _apply_delta(client, company_id: str, product: ProductFact, delta: int) -> Dict[str, Any]:
    """Atomically move stock by `delta`, refusing to go negative."""
    from firebase_admin import firestore

    ref = _company_ref(client, company_id).collection("products").document(product.id)
    location = product.location

    @firestore.transactional
    def _txn(transaction):
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            return {"ok": False, "error": "product no longer exists"}
        data = snapshot.to_dict() or {}
        old = int(data.get("quantity", 0) or 0)
        new = old + delta
        if new < 0:
            return {
                "ok": False,
                "error": f"insufficient stock: {old} on hand, tried to remove {abs(delta)}",
                "old_stock": old,
            }
        update: Dict[str, Any] = {"quantity": new, "updatedAt": datetime.now(timezone.utc)}
        if location:
            loc_map = dict(data.get("locationQuantities") or {})
            loc_map[location] = max(0, int(loc_map.get(location, 0) or 0) + delta)
            update["locationQuantities"] = loc_map
        transaction.update(ref, update)
        return {"ok": True, "old_stock": old, "new_stock": new}

    return _txn(client.transaction())


def _offline(company_id: str, product: ProductFact, delta: int, reason: str) -> Dict[str, Any]:
    from inventory_db import db_instance

    return db_instance.update_stock(
        product.barcode, delta, reason, company_id=company_id
    )


# ---------------------------------------------------------------------------
# Public operations
# ---------------------------------------------------------------------------

def update_stock(
    product: ProductFact,
    qty_change: int,
    reason: str = "AI adjustment",
    company_id: str = "default",
) -> Dict[str, Any]:
    qty_change = int(qty_change)
    if qty_change == 0:
        return {"success": False, "error": "quantity change cannot be zero"}

    client = _client()
    if client is None or os.environ.get("OFFLINE_MODE") == "1":
        res = _offline(company_id, product, qty_change, reason)
        fact_store.bump(company_id)
        return res

    result = _apply_delta(client, company_id, product, qty_change)
    if not result.get("ok"):
        return {"success": False, "error": result.get("error", "update failed")}

    tx_type = "stock_in" if qty_change > 0 else "stock_out"
    if "damage" in reason.lower():
        tx_type = "damage"
    _write_transaction(client, company_id, product, tx_type, qty_change, reason)

    entry = {
        "action": "update_stock",
        "barcode": product.barcode,
        "product_name": product.name,
        "old_stock": result["old_stock"],
        "new_stock": result["new_stock"],
        "qty_change": qty_change,
        "reason": reason,
    }
    _log_ledger(company_id, entry)
    fact_store.bump(company_id)

    return {
        "success": True,
        "product_name": product.name,
        "barcode": product.barcode,
        "old_stock": result["old_stock"],
        "new_stock": result["new_stock"],
        "qty_change": qty_change,
    }


def create_purchase_order(
    product: ProductFact,
    reorder_qty: int,
    supplier_name: str = "",
    company_id: str = "default",
) -> Dict[str, Any]:
    reorder_qty = int(reorder_qty)
    if reorder_qty <= 0:
        return {"success": False, "error": "reorder quantity must be positive"}

    po_id = f"PO-{int(datetime.now(timezone.utc).timestamp())}"
    total_cost = round(reorder_qty * product.cost_price, 2)
    supplier = supplier_name or product.vendor_name or "Default Supplier"

    entry = {
        "action": "create_purchase_order",
        "po_id": po_id,
        "barcode": product.barcode,
        "product_name": product.name,
        "reorder_qty": reorder_qty,
        "supplier": supplier,
        "unit_cost": product.cost_price,
        "total_cost": total_cost,
        "status": "DRAFT",
    }
    _log_ledger(company_id, entry)

    return {
        "success": True,
        "po_id": po_id,
        "product_name": product.name,
        "barcode": product.barcode,
        "reorder_qty": reorder_qty,
        "supplier": supplier,
        "total_cost": total_cost,
        "note": "Purchase order drafted. Stock updates when the delivery is received.",
    }


def audit_inventory(
    product: ProductFact,
    actual_stock: int,
    notes: str = "Physical audit",
    company_id: str = "default",
) -> Dict[str, Any]:
    actual_stock = max(0, int(actual_stock))
    delta = actual_stock - product.quantity
    if delta == 0:
        return {
            "success": True,
            "product_name": product.name,
            "barcode": product.barcode,
            "discrepancy": 0,
            "note": "Counted quantity matches the system — nothing to adjust.",
        }

    client = _client()
    if client is None or os.environ.get("OFFLINE_MODE") == "1":
        from inventory_db import db_instance

        res = db_instance.audit_inventory(
            product.barcode, actual_stock, notes, company_id=company_id
        )
        fact_store.bump(company_id)
        return res

    result = _apply_delta(client, company_id, product, delta)
    if not result.get("ok"):
        return {"success": False, "error": result.get("error", "audit failed")}

    _write_transaction(
        client, company_id, product, "adjustment", delta, f"Audit: {notes}"
    )
    _log_ledger(
        company_id,
        {
            "action": "audit_inventory",
            "barcode": product.barcode,
            "product_name": product.name,
            "old_stock": result["old_stock"],
            "actual_stock": actual_stock,
            "discrepancy": delta,
            "notes": notes,
        },
    )
    fact_store.bump(company_id)
    return {
        "success": True,
        "product_name": product.name,
        "barcode": product.barcode,
        "old_stock": result["old_stock"],
        "actual_stock": actual_stock,
        "discrepancy": delta,
    }


def transfer_stock(
    product: ProductFact,
    from_location: str,
    to_location: str,
    qty: int,
    company_id: str = "default",
) -> Dict[str, Any]:
    qty = int(qty)
    if qty <= 0:
        return {"success": False, "error": "transfer quantity must be positive"}

    available_at_source = product.location_quantities.get(from_location)
    if available_at_source is not None and available_at_source < qty:
        return {
            "success": False,
            "error": f"only {available_at_source} units at {from_location}",
        }
    if product.quantity < qty:
        return {"success": False, "error": f"only {product.quantity} units on hand"}

    client = _client()
    if client is None or os.environ.get("OFFLINE_MODE") == "1":
        from inventory_db import db_instance

        res = db_instance.transfer_stock(
            product.barcode, from_location, to_location, qty, company_id=company_id
        )
        fact_store.bump(company_id)
        return res

    from firebase_admin import firestore

    ref = _company_ref(client, company_id).collection("products").document(product.id)

    @firestore.transactional
    def _txn(transaction):
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            return {"ok": False, "error": "product no longer exists"}
        data = snapshot.to_dict() or {}
        loc_map = dict(data.get("locationQuantities") or {})
        source = int(loc_map.get(from_location, 0) or 0)
        if source < qty:
            return {"ok": False, "error": f"only {source} units at {from_location}"}
        loc_map[from_location] = source - qty
        loc_map[to_location] = int(loc_map.get(to_location, 0) or 0) + qty
        transaction.update(
            ref,
            {"locationQuantities": loc_map, "updatedAt": datetime.now(timezone.utc)},
        )
        return {"ok": True}

    result = _txn(client.transaction())
    if not result.get("ok"):
        return {"success": False, "error": result.get("error", "transfer failed")}

    _write_transaction(
        client,
        company_id,
        product,
        "transfer",
        qty,
        f"Transfer {from_location} to {to_location}",
        location=to_location,
    )
    _log_ledger(
        company_id,
        {
            "action": "transfer_stock",
            "barcode": product.barcode,
            "product_name": product.name,
            "from_location": from_location,
            "to_location": to_location,
            "qty": qty,
        },
    )
    fact_store.bump(company_id)
    return {
        "success": True,
        "product_name": product.name,
        "from_location": from_location,
        "to_location": to_location,
        "qty": qty,
    }


def set_min_threshold(
    product: ProductFact, new_threshold: int, company_id: str = "default"
) -> Dict[str, Any]:
    new_threshold = max(0, int(new_threshold))
    client = _client()
    if client is None or os.environ.get("OFFLINE_MODE") == "1":
        from inventory_db import db_instance

        res = db_instance.set_min_threshold(
            product.barcode, new_threshold, company_id=company_id
        )
        fact_store.bump(company_id)
        return res

    try:
        _company_ref(client, company_id).collection("products").document(product.id).set(
            {
                "lowStockThreshold": new_threshold,
                "updatedAt": datetime.now(timezone.utc),
            },
            merge=True,
        )
    except Exception as exc:
        return {"success": False, "error": str(exc)}

    _log_ledger(
        company_id,
        {
            "action": "set_min_threshold",
            "barcode": product.barcode,
            "product_name": product.name,
            "old_threshold": product.min_threshold,
            "new_threshold": new_threshold,
        },
    )
    fact_store.bump(company_id)
    return {
        "success": True,
        "product_name": product.name,
        "barcode": product.barcode,
        "old_threshold": product.min_threshold,
        "new_threshold": new_threshold,
    }
