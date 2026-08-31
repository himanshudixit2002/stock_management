"""Predictive endpoints, now backed by the fact layer.

This suite used to unit-test `predictive_ml` helpers that computed forecasts
from a `sales_velocity` field the app never wrote, so every number was derived
from 0.0. Those helpers are gone; `facts.py` derives demand from the real
transaction ledger and `test_facts.py` covers that math directly.

What is still worth asserting here is the HTTP contract: the shapes the Flutter
dashboards read, and that a company with no movement history is reported as
unknown rather than given a fabricated forecast.
"""

import sys

import testkit
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)
_failures = []


def check(label, ok, detail=""):
    if not ok:
        _failures.append(f"{label} {detail}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  -- {detail}" if detail else ""))


testkit.seed()
H = testkit.headers()

print("\n== A company id is mandatory ==")
check("forecast without a company id is refused",
      client.get("/api/agent/forecast").status_code == 400)
check("safety stock without a company id is refused",
      client.get("/api/agent/safety_stock").status_code == 400)

print("\n== Forecast endpoint ==")
res = client.get("/api/agent/forecast", headers=H)
check("returns 200", res.status_code == 200, str(res.status_code))
body = res.json()
forecasts = body.get("forecasts", [])
check("covers every product", len(forecasts) == 4, f"{len(forecasts)} rows")
check("reports history availability", "has_sales_history" in body,
      str(body.get("has_sales_history")))

required = {
    "barcode", "product_name", "current_stock", "daily_sales_rate",
    "days_until_stockout", "risk_level", "recommendation",
}
check("keeps the keys the dashboard reads",
      required.issubset(forecasts[0].keys()),
      str(sorted(required - set(forecasts[0].keys()))))

print("\n== No ledger means unknown, not a fabricated forecast ==")
# The seeded company has no transactions at all.
check("every SKU flagged UNKNOWN",
      all(f["risk_level"] == "UNKNOWN" for f in forecasts),
      str({f["risk_level"] for f in forecasts}))
check("no invented demand",
      all(f["daily_sales_rate"] == 0 for f in forecasts))
# Being below a user-set safety threshold is a real, actionable fact that needs
# no demand history, so those still get a reorder recommendation. Only the
# SKUs that would need demand data to judge should say the demand is unknown.
below = [f for f in forecasts if f["current_stock"] < 50 and "Apples" in f["product_name"]]
healthy = [f for f in forecasts if f["product_name"].startswith(("Pro Laptops", "Sparkling"))]
check("threshold breach still gets concrete advice",
      all("order" in f["recommendation"].lower() for f in below),
      below[0]["recommendation"] if below else "none")
check("well-stocked SKUs say demand is unknown rather than guessing",
      all("unknown" in f["recommendation"].lower() for f in healthy),
      healthy[0]["recommendation"] if healthy else "none")

print("\n== Safety stock endpoint ==")
res = client.get("/api/agent/safety_stock", headers=H)
check("returns 200", res.status_code == 200)
body = res.json()
check("classifies every SKU", len(body.get("recommendations", [])) == 4)
check("reports an ABC split", "abc_analysis_summary" in body,
      str(body.get("abc_analysis_summary")))

print("\n== Autopilot endpoint ==")
res = client.get("/api/agent/autopilot", headers=H)
check("returns 200", res.status_code == 200)
recs = res.json().get("recommendations", [])
check("flags the two products below threshold", len(recs) == 2,
      f"{[r['product_name'] for r in recs]}")
check("keeps weekly velocity for the dashboard",
      all("weekly_sales_velocity" in r for r in recs))

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All predictive endpoint tests passed.")
