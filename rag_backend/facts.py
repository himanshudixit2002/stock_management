"""
Fact layer — the single source of truth the AI reasons over.

Pulls products, a rolling window of stock transactions, and vendors straight
from Firestore, then derives *real* demand statistics from the transaction
ledger (burn rate, demand sigma, days of cover, dead stock, available-to-promise).

The derived math intentionally mirrors
`lib/services/report_analytics_service.dart::computeInventoryHealthForecasts`
so the assistant and the app's Reports screen can never disagree.

Every snapshot carries a `version` stamp. Any write bumps it, which invalidates
every cached answer for that company without relying on TTL guesswork.
"""

from __future__ import annotations

import hashlib
import math
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

WINDOW_DAYS = int(os.environ.get("FACTS_WINDOW_DAYS", "90"))
RECENT_DAYS = int(os.environ.get("FACTS_RECENT_DAYS", "30"))
TTL_SECONDS = float(os.environ.get("FACTS_TTL_SECONDS", "45"))
MAX_PRODUCTS = int(os.environ.get("FACTS_MAX_PRODUCTS", "2000"))
MAX_TRANSACTIONS = int(os.environ.get("FACTS_MAX_TRANSACTIONS", "20000"))
DEFAULT_LEAD_TIME_DAYS = int(os.environ.get("DEFAULT_LEAD_TIME_DAYS", "3"))

# Service-level factor for statistical safety stock (1.65 ~ 95% fill rate).
SERVICE_Z = float(os.environ.get("SERVICE_LEVEL_Z", "1.65"))

# Health quadrant thresholds — kept in lockstep with the Dart implementation.
AT_RISK_DAYS = 14.0
OVERSTOCKED_DAYS = 90.0
OVERSTOCKED_MIN_QTY = 15

# Below this share of the catalog showing any movement, the ledger cannot tell
# "genuinely not selling" apart from "not being recorded". Calling a product
# dead stock on that basis is an inference the data does not support, so those
# products are marked `no_history` instead.
MIN_HISTORY_COVERAGE = float(os.environ.get("MIN_HISTORY_COVERAGE", "0.05"))

_OUT_TYPES = {"stock_out", "damage"}
_IN_TYPES = {"stock_in"}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _to_dt(value: Any) -> Optional[datetime]:
    """Coerce a Firestore timestamp / datetime / epoch into an aware datetime."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, (int, float)):
        # Firestore never stores epoch ints for dates, but imports sometimes do.
        seconds = value / 1000.0 if value > 1e11 else float(value)
        try:
            return datetime.fromtimestamp(seconds, tz=timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    to_datetime = getattr(value, "to_datetime", None)
    if callable(to_datetime):
        try:
            dt = to_datetime()
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None
    return None


def _num(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return default
    return default


def _int(value: Any, default: int = 0) -> int:
    return int(_num(value, float(default)))


def _text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    s = str(value).strip()
    return s or default


@dataclass
class ProductFact:
    """One product, plus everything the agent needs to reason about it."""

    id: str
    barcode: str
    name: str
    category: str = "General"
    unit: str = "pcs"

    quantity: int = 0
    held_quantity: int = 0
    available_qty: int = 0
    min_threshold: int = 10

    cost_price: float = 0.0
    selling_price: float = 0.0

    location: str = ""
    location_quantities: Dict[str, int] = field(default_factory=dict)

    vendor_id: str = ""
    vendor_name: str = ""
    lead_time_days: int = DEFAULT_LEAD_TIME_DAYS

    # --- derived from the transaction ledger ---
    units_out_window: int = 0
    units_in_window: int = 0
    units_out_recent: int = 0
    daily_burn_rate: float = 0.0
    daily_burn_rate_recent: float = 0.0
    demand_std_dev: float = 0.0
    days_of_supply: float = 0.0
    days_of_supply_available: float = 0.0
    last_sold_at: Optional[str] = None
    days_since_last_sale: Optional[int] = None
    health: str = "optimal"

    # --- replenishment math ---
    safety_stock: int = 0
    reorder_point: int = 0
    suggested_reorder_qty: int = 0
    needs_reorder: bool = False

    @property
    def stock_value(self) -> float:
        return self.quantity * self.selling_price

    @property
    def cost_value(self) -> float:
        return self.quantity * self.cost_price

    @property
    def is_out_of_stock(self) -> bool:
        return self.quantity <= 0

    @property
    def is_low_stock(self) -> bool:
        return 0 < self.quantity <= self.min_threshold

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    def brief(self) -> Dict[str, Any]:
        """Compact form for LLM tool results — every field earns its tokens."""
        out: Dict[str, Any] = {
            "name": self.name,
            "barcode": self.barcode,
            "stock": self.quantity,
            "available": self.available_qty,
            "min": self.min_threshold,
            "burn_per_day": round(self.daily_burn_rate, 2),
            "days_of_cover": (
                None if self.days_of_supply >= 999 else round(self.days_of_supply, 1)
            ),
            "health": self.health,
        }
        if self.held_quantity:
            out["held"] = self.held_quantity
        if self.needs_reorder:
            out["reorder_point"] = self.reorder_point
            out["suggested_reorder_qty"] = self.suggested_reorder_qty
        if self.selling_price:
            out["price"] = round(self.selling_price, 2)
        return out

    def context_line(self) -> str:
        """One dense line for prompt context."""
        bits = [
            f"{self.name} (BC {self.barcode})",
            f"stock {self.quantity}",
        ]
        if self.held_quantity:
            bits.append(f"available {self.available_qty} ({self.held_quantity} held)")
        bits.append(f"min {self.min_threshold}")
        if self.daily_burn_rate > 0:
            bits.append(f"burn {self.daily_burn_rate:.2f}/day")
            if self.days_of_supply < 999:
                bits.append(f"{self.days_of_supply:.0f}d cover")
        else:
            bits.append("no sales in window")
        if self.selling_price:
            bits.append(f"price {self.selling_price:.2f}")
        bits.append(self.health)
        return "- " + " | ".join(bits)


@dataclass
class InventoryFacts:
    company_id: str
    version: int
    generated_at: float
    window_days: int
    products: List[ProductFact] = field(default_factory=list)
    source: str = "firestore"
    warnings: List[str] = field(default_factory=list)
    fingerprint: str = ""

    # The company's own vocabulary. Creating a product means choosing from
    # these, not inventing a category or a shelf name that no screen will
    # recognise afterwards.
    categories: List[Dict[str, str]] = field(default_factory=list)
    configured_locations: List[str] = field(default_factory=list)

    _by_id: Dict[str, ProductFact] = field(default_factory=dict, repr=False)
    _by_barcode: Dict[str, ProductFact] = field(default_factory=dict, repr=False)

    def index(self) -> "InventoryFacts":
        self._by_id = {p.id: p for p in self.products if p.id}
        self._by_barcode = {p.barcode: p for p in self.products if p.barcode}
        self._apply_history_confidence()
        self.fingerprint = self._fingerprint()
        return self

    @property
    def history_coverage(self) -> float:
        """Share of the catalog with any recorded movement in the window."""
        if not self.products:
            return 0.0
        moved = sum(1 for p in self.products if p.units_out_window > 0)
        return moved / len(self.products)

    @property
    def history_is_reliable(self) -> bool:
        return self.history_coverage >= MIN_HISTORY_COVERAGE

    def _apply_history_confidence(self) -> None:
        """Downgrade `dead_stock` to `no_history` when the ledger is too sparse.

        Per-product derivation is deliberately Dart-identical and has no view of
        the catalog. This pass adds the judgement that only catalog-wide
        information can support: if almost nothing has moved, absence of
        movement is evidence about the *record keeping*, not about demand.
        """
        if self.history_is_reliable:
            return
        for p in self.products:
            if p.health == "dead_stock":
                p.health = "no_history"

    def _fingerprint(self) -> str:
        """Content hash of the inventory state.

        Deriving the cache key from *content* rather than a per-process counter
        means every Cloud Run instance agrees on it, so a stock change
        invalidates cached answers everywhere without any coordination.
        """
        digest = hashlib.sha256()
        for p in sorted(self.products, key=lambda x: x.id or x.barcode):
            digest.update(
                f"{p.id}:{p.quantity}:{p.held_quantity}:{p.min_threshold}:"
                f"{p.cost_price}:{p.selling_price}:{p.units_out_window}|".encode()
            )
        return digest.hexdigest()[:16]

    def by_id(self, pid: str) -> Optional[ProductFact]:
        return self._by_id.get(str(pid).strip())

    def by_barcode(self, barcode: str) -> Optional[ProductFact]:
        return self._by_barcode.get(str(barcode).strip())

    def lookup(self, key: str) -> Optional[ProductFact]:
        k = str(key or "").strip()
        if not k:
            return None
        return self._by_barcode.get(k) or self._by_id.get(k)

    # ---------------- aggregates ----------------

    @property
    def out_of_stock(self) -> List[ProductFact]:
        return [p for p in self.products if p.is_out_of_stock]

    @property
    def low_stock(self) -> List[ProductFact]:
        return [p for p in self.products if p.is_low_stock]

    @property
    def dead_stock(self) -> List[ProductFact]:
        return [p for p in self.products if p.health == "dead_stock"]

    def inconsistencies(self) -> List[Dict[str, Any]]:
        """Products whose total disagrees with the sum of their locations.

        The app reads both numbers, so a product in this state shows different
        stock on different screens. Reporting is deliberate: only a human knows
        whether the total or the shelves are the truth, so this never guesses a
        repair.
        """
        found = []
        for p in self.products:
            if not p.location_quantities:
                continue
            located = sum(p.location_quantities.values())
            if located != p.quantity:
                found.append(
                    {
                        "id": p.id,
                        "barcode": p.barcode,
                        "name": p.name,
                        "quantity": p.quantity,
                        "located_total": located,
                        "difference": p.quantity - located,
                        "locations": dict(p.location_quantities),
                    }
                )
        return sorted(found, key=lambda r: -abs(r["difference"]))

    @property
    def known_locations(self) -> List[str]:
        """Configured locations plus any already holding stock."""
        seen = {loc for loc in self.configured_locations}
        for p in self.products:
            seen.update(k for k, v in p.location_quantities.items() if k)
        return sorted(seen)

    def category_by_name(self, name: str) -> Optional[Dict[str, str]]:
        want = (name or "").strip().lower()
        if not want:
            return None
        for c in self.categories:
            if c["name"].lower() == want:
                return c
        for c in self.categories:
            if want in c["name"].lower() or c["name"].lower() in want:
                return c
        return None

    @property
    def untracked(self) -> List[ProductFact]:
        """Products with no movement, in a catalog too sparse to judge them."""
        return [p for p in self.products if p.health == "no_history"]

    @property
    def overstocked(self) -> List[ProductFact]:
        return [p for p in self.products if p.health == "overstocked"]

    @property
    def at_risk(self) -> List[ProductFact]:
        return [p for p in self.products if p.health == "at_risk"]

    @property
    def needs_reorder(self) -> List[ProductFact]:
        items = [p for p in self.products if p.needs_reorder]
        items.sort(key=lambda p: (p.days_of_supply, -p.daily_burn_rate))
        return items

    def summary(self) -> Dict[str, Any]:
        total_value = sum(p.stock_value for p in self.products)
        total_cost = sum(p.cost_value for p in self.products)
        held = sum(p.held_quantity for p in self.products)
        dead = self.dead_stock
        untracked = self.untracked
        return {
            "total_products": len(self.products),
            "low_stock_count": len(self.low_stock),
            "out_of_stock_count": len(self.out_of_stock),
            "at_risk_count": len(self.at_risk),
            "dead_stock_count": len(dead),
            "dead_stock_value": round(sum(p.cost_value for p in dead), 2),
            "untracked_count": len(untracked),
            "history_coverage_pct": round(self.history_coverage * 100, 1),
            "history_is_reliable": self.history_is_reliable,
            "overstocked_count": len(self.overstocked),
            "reorder_count": len(self.needs_reorder),
            "held_units": held,
            "total_inventory_value": round(total_value, 2),
            "total_cost_value": round(total_cost, 2),
            "unrealized_margin": round(total_value - total_cost, 2),
            "window_days": self.window_days,
            "has_sales_history": any(p.units_out_window > 0 for p in self.products),
        }

    def summary_line(self) -> str:
        s = self.summary()
        line = (
            f"INVENTORY ({s['total_products']} SKUs): {s['low_stock_count']} low, "
            f"{s['out_of_stock_count']} out, {s['reorder_count']} below reorder point. "
            f"Retail value {s['total_inventory_value']:,.2f}, cost basis {s['total_cost_value']:,.2f}."
        )
        if s["history_is_reliable"]:
            line += f" {s['dead_stock_count']} dead stock (no sales in {self.window_days}d)."
        else:
            line += (
                f" DEMAND DATA UNAVAILABLE: only {s['history_coverage_pct']}% of the catalog "
                f"has any recorded stock movement in the last {self.window_days} days, so burn "
                f"rates, days-of-cover and dead-stock judgements cannot be made. "
                f"{s['untracked_count']} SKUs have no movement recorded — that means they are "
                f"NOT BEING TRACKED, not that they are not selling. Never describe them as dead "
                f"stock or as capital being wasted, and never present this as a business risk. "
                f"If asked about demand, say the transaction history is missing and recommend "
                f"recording stock-out movements."
            )
        return line


# ---------------------------------------------------------------------------
# Derivation
# ---------------------------------------------------------------------------

def _primary_location(location_quantities: Dict[str, int]) -> str:
    if not location_quantities:
        return ""
    best, best_qty = "", -1
    for loc, qty in location_quantities.items():
        q = _int(qty)
        if q > best_qty:
            best, best_qty = str(loc), q
    return best


def _std_dev(daily: List[float]) -> float:
    n = len(daily)
    if n < 2:
        return 0.0
    mean = sum(daily) / n
    variance = sum((d - mean) ** 2 for d in daily) / (n - 1)
    return math.sqrt(max(0.0, variance))


def derive_product_fact(
    raw: Dict[str, Any],
    tx_by_product: Dict[str, List[Tuple[datetime, str, int]]],
    vendors: Dict[str, Dict[str, Any]],
    window_days: int,
    now: datetime,
) -> ProductFact:
    """Turn one raw product doc plus its transaction history into a ProductFact."""
    pid = _text(raw.get("id"))
    barcode = _text(raw.get("barcode")) or pid
    loc_qty = {
        str(k): _int(v) for k, v in (raw.get("locationQuantities") or {}).items()
    }

    quantity = _int(raw.get("quantity"))
    held = max(0, _int(raw.get("heldQuantity")))

    vendor_id = _text(raw.get("preferredVendorId")) or _text(raw.get("lastVendorId"))
    vendor = vendors.get(vendor_id, {})
    lead_time = _int(vendor.get("leadTimeDays"), 0)
    if lead_time <= 0:
        lead_time = DEFAULT_LEAD_TIME_DAYS

    fact = ProductFact(
        id=pid,
        barcode=barcode,
        name=_text(raw.get("name"), "Unnamed Product"),
        category=_text(raw.get("categoryName"), "General"),
        unit=_text(raw.get("unit"), "pcs"),
        quantity=quantity,
        held_quantity=held,
        available_qty=max(0, quantity - held),
        min_threshold=max(0, _int(raw.get("lowStockThreshold"), 10)),
        cost_price=round(_num(raw.get("costPrice")), 4),
        selling_price=round(_num(raw.get("sellingPrice")), 4),
        location=_primary_location(loc_qty),
        location_quantities=loc_qty,
        vendor_id=vendor_id,
        vendor_name=_text(raw.get("preferredVendorName")) or _text(vendor.get("name")),
        lead_time_days=lead_time,
    )

    # ---- demand statistics from the ledger ----
    window_start = now - timedelta(days=window_days)
    recent_start = now - timedelta(days=RECENT_DAYS)
    daily_out: Dict[int, float] = {}
    last_sold: Optional[datetime] = None

    for when, kind, qty in tx_by_product.get(pid, ()):
        if when < window_start:
            continue
        if kind in _OUT_TYPES:
            fact.units_out_window += qty
            day_index = (when - window_start).days
            daily_out[day_index] = daily_out.get(day_index, 0.0) + qty
            if when >= recent_start:
                fact.units_out_recent += qty
            if last_sold is None or when > last_sold:
                last_sold = when
        elif kind in _IN_TYPES:
            fact.units_in_window += qty

    # Matches the Dart: total out over the period / period days.
    fact.daily_burn_rate = round(fact.units_out_window / max(window_days, 1), 4)
    fact.daily_burn_rate_recent = round(fact.units_out_recent / max(RECENT_DAYS, 1), 4)

    # sigma over every day in the window, zero-days included — that is the
    # variability safety stock actually has to absorb.
    if fact.units_out_window > 0:
        series = [daily_out.get(i, 0.0) for i in range(window_days)]
        fact.demand_std_dev = round(_std_dev(series), 4)

    if last_sold is not None:
        fact.last_sold_at = last_sold.isoformat()
        fact.days_since_last_sale = max(0, (now - last_sold).days)

    if fact.daily_burn_rate > 0:
        fact.days_of_supply = round(fact.quantity / fact.daily_burn_rate, 2)
        fact.days_of_supply_available = round(
            fact.available_qty / fact.daily_burn_rate, 2
        )
    else:
        fact.days_of_supply = 999.0 if fact.quantity > 0 else 0.0
        fact.days_of_supply_available = 999.0 if fact.available_qty > 0 else 0.0

    # ---- health quadrant (same thresholds as the Reports screen) ----
    if fact.quantity <= 0 or fact.days_of_supply < AT_RISK_DAYS:
        fact.health = "at_risk"
    elif fact.units_out_window == 0:
        fact.health = "dead_stock"
    elif fact.days_of_supply > OVERSTOCKED_DAYS and fact.quantity > OVERSTOCKED_MIN_QTY:
        fact.health = "overstocked"
    else:
        fact.health = "optimal"

    # ---- replenishment ----
    sigma = fact.demand_std_dev or (fact.daily_burn_rate * 0.3)
    if fact.daily_burn_rate > 0 and sigma > 0:
        fact.safety_stock = max(
            1, round(SERVICE_Z * sigma * math.sqrt(max(1, fact.lead_time_days)))
        )
    else:
        fact.safety_stock = 0

    fact.reorder_point = max(
        fact.min_threshold,
        round(fact.daily_burn_rate * fact.lead_time_days) + fact.safety_stock,
    )
    fact.needs_reorder = fact.available_qty <= fact.reorder_point

    if fact.needs_reorder:
        # Cover lead time plus a review cycle, then top up to that target.
        review_days = max(fact.lead_time_days, 14)
        target = round(fact.daily_burn_rate * (fact.lead_time_days + review_days)) + fact.safety_stock
        target = max(target, fact.min_threshold * 2)
        fact.suggested_reorder_qty = max(1, target - fact.available_qty)

    return fact


# ---------------------------------------------------------------------------
# Firestore loading
# ---------------------------------------------------------------------------

def _firestore_client():
    try:
        from inventory_db import db_firestore  # shared, already-initialised app
        return db_firestore
    except Exception:
        return None


def _load_products(client, company_id: str) -> List[Dict[str, Any]]:
    docs = (
        client.collection("companies")
        .document(company_id)
        .collection("products")
        .limit(MAX_PRODUCTS)
        .stream()
    )
    out = []
    for doc in docs:
        data = doc.to_dict() or {}
        data["id"] = doc.id
        out.append(data)
    return out


def _load_transactions(
    client, company_id: str, since: datetime
) -> Dict[str, List[Tuple[datetime, str, int]]]:
    collection = (
        client.collection("companies").document(company_id).collection("transactions")
    )
    try:
        # Positional `where` is deprecated in google-cloud-firestore.
        from google.cloud.firestore_v1.base_query import FieldFilter

        query = collection.where(filter=FieldFilter("date", ">=", since))
    except Exception:
        query = collection.where("date", ">=", since)
    query = query.order_by("date", direction="DESCENDING").limit(MAX_TRANSACTIONS)
    grouped: Dict[str, List[Tuple[datetime, str, int]]] = {}
    for doc in query.stream():
        data = doc.to_dict() or {}
        pid = _text(data.get("productId"))
        if not pid:
            continue
        when = _to_dt(data.get("date"))
        if when is None:
            continue
        qty = abs(_int(data.get("quantity")))
        if qty == 0:
            continue
        grouped.setdefault(pid, []).append((when, _text(data.get("type")), qty))
    return grouped


def _load_categories(client, company_id: str) -> List[Dict[str, str]]:
    docs = (
        client.collection("companies")
        .document(company_id)
        .collection("categories")
        .limit(200)
        .stream()
    )
    out = []
    for doc in docs:
        data = doc.to_dict() or {}
        name = _text(data.get("name"))
        if name:
            out.append({"id": doc.id, "name": name})
    return sorted(out, key=lambda c: c["name"].lower())


def _load_locations(client, company_id: str) -> List[str]:
    """The locations the company has configured in settings."""
    try:
        snap = client.collection("companies").document(company_id).get()
        if not snap.exists:
            return []
        data = snap.to_dict() or {}
        raw = data.get("settings.locations")
        if raw is None:
            raw = (data.get("settings") or {}).get("locations")
        return [str(v).strip() for v in (raw or []) if str(v).strip()]
    except Exception:
        return []


def _load_vendors(client, company_id: str) -> Dict[str, Dict[str, Any]]:
    docs = (
        client.collection("companies")
        .document(company_id)
        .collection("vendors")
        .limit(500)
        .stream()
    )
    return {doc.id: (doc.to_dict() or {}) for doc in docs}


# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

class FactStore:
    """TTL-cached, version-stamped inventory snapshots, one per company."""

    def __init__(self, ttl_seconds: float = TTL_SECONDS, window_days: int = WINDOW_DAYS):
        self.ttl = ttl_seconds
        self.window_days = window_days
        self._lock = threading.RLock()
        self._cache: Dict[str, InventoryFacts] = {}
        self._versions: Dict[str, int] = {}
        self._loads = 0
        self._serves = 0

    # -- versioning --------------------------------------------------------

    def version(self, company_id: str) -> int:
        return self._versions.get(self._cid(company_id), 0)

    def bump(self, company_id: str) -> int:
        """Invalidate a company's snapshot after a write."""
        cid = self._cid(company_id)
        with self._lock:
            self._versions[cid] = self._versions.get(cid, 0) + 1
            self._cache.pop(cid, None)
            return self._versions[cid]

    @staticmethod
    def _cid(company_id: Optional[str]) -> str:
        return (company_id or "default").strip() or "default"

    # -- access ------------------------------------------------------------

    def get(self, company_id: Optional[str] = "default", force: bool = False) -> InventoryFacts:
        cid = self._cid(company_id)
        now = time.time()
        with self._lock:
            cached = self._cache.get(cid)
            if cached and not force and (now - cached.generated_at) < self.ttl:
                self._serves += 1
                return cached

        facts = self._build(cid)
        with self._lock:
            self._cache[cid] = facts
            self._loads += 1
        return facts

    def stats(self) -> Dict[str, Any]:
        return {
            "companies_cached": len(self._cache),
            "loads": self._loads,
            "cache_serves": self._serves,
            "ttl_seconds": self.ttl,
            "window_days": self.window_days,
        }

    # -- building ----------------------------------------------------------

    def _build(self, company_id: str) -> InventoryFacts:
        now = _now()
        version = self._versions.get(company_id, 0)
        client = _firestore_client()
        warnings: List[str] = []
        source = "firestore"

        raw_products: List[Dict[str, Any]] = []
        tx: Dict[str, List[Tuple[datetime, str, int]]] = {}
        vendors: Dict[str, Dict[str, Any]] = {}
        categories: List[Dict[str, str]] = []
        configured_locations: List[str] = []

        offline = os.environ.get("OFFLINE_MODE") == "1"

        if client is not None and not offline:
            since = now - timedelta(days=self.window_days)
            with ThreadPoolExecutor(max_workers=3) as pool:
                f_products = pool.submit(_load_products, client, company_id)
                f_tx = pool.submit(_load_transactions, client, company_id, since)
                f_vendors = pool.submit(_load_vendors, client, company_id)
                f_cats = pool.submit(_load_categories, client, company_id)
                f_locs = pool.submit(_load_locations, client, company_id)
                try:
                    raw_products = f_products.result()
                except Exception as exc:
                    warnings.append(f"product load failed: {exc}")
                try:
                    tx = f_tx.result()
                except Exception as exc:
                    warnings.append(f"transaction load failed: {exc}")
                try:
                    vendors = f_vendors.result()
                except Exception as exc:
                    warnings.append(f"vendor load failed: {exc}")
                try:
                    categories = f_cats.result()
                except Exception as exc:
                    warnings.append(f"category load failed: {exc}")
                try:
                    configured_locations = f_locs.result()
                except Exception as exc:
                    warnings.append(f"location load failed: {exc}")

        # The local JSON store is a development convenience only. Silently
        # falling back to it in production is what let one tenant be shown
        # another's data, so it is now reachable exclusively via OFFLINE_MODE.
        # A company with no products in Firestore legitimately has an empty
        # catalog, and the assistant should say so rather than invent one.
        if offline or client is None:
            raw_products = self._local_products(company_id)
            source = "local" if raw_products else "empty"
            if client is None and not offline:
                warnings.append(
                    "No Firestore client available; serving the local snapshot. "
                    "Set OFFLINE_MODE=1 to make this explicit."
                )
        elif not raw_products:
            source = "empty"

        products = [
            derive_product_fact(raw, tx, vendors, self.window_days, now)
            for raw in raw_products
        ]

        facts = InventoryFacts(
            company_id=company_id,
            version=version,
            generated_at=time.time(),
            window_days=self.window_days,
            products=products,
            source=source,
            warnings=warnings,
            categories=categories,
            configured_locations=configured_locations,
        )
        for warning in warnings:
            print(f"[FactStore:{company_id}] {warning}")
        return facts.index()

    @staticmethod
    def _local_products(company_id: str) -> List[Dict[str, Any]]:
        """Offline/dev fallback: adapt the local JSON store to the Firestore shape."""
        try:
            from inventory_db import db_instance
        except Exception:
            return []
        adapted = []
        for p in db_instance.get_all_products(company_id=company_id):
            adapted.append(
                {
                    "id": _text(p.get("id")) or _text(p.get("barcode")),
                    "barcode": _text(p.get("barcode")),
                    "name": p.get("name"),
                    "quantity": p.get("stock", 0),
                    "heldQuantity": p.get("held_quantity", 0),
                    "lowStockThreshold": p.get("min_threshold", 10),
                    "categoryName": p.get("category", "General"),
                    "costPrice": p.get("cost_price", 0.0),
                    "sellingPrice": p.get("selling_price", 0.0),
                    "locationQuantities": p.get("location_quantities") or (
                        {p["location"]: p.get("stock", 0)} if p.get("location") else {}
                    ),
                    "preferredVendorId": p.get("vendor_id", ""),
                    "preferredVendorName": p.get("vendor_name", ""),
                }
            )
        return adapted


fact_store = FactStore()
