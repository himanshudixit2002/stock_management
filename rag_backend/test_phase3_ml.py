import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from predictive_ml import (
    predict_30day_demand_forecast,
    calculate_statistical_safety_stock,
    calculate_stockout_risk_timeline,
    perform_abc_analysis
)
from inventory_db import db_instance

def test_30day_forecast():
    print("--- 1. Testing 30-Day Demand Forecast Curves ---")
    product = {
        "barcode": "TEST-SKU-F1",
        "name": "Predictive Test Widget",
        "stock": 50,
        "sales_velocity": 4.0,
        "lead_time_days": 5,
        "cost_price": 20.0,
        "selling_price": 40.0
    }
    
    curve = predict_30day_demand_forecast(product, days=30)
    assert len(curve) == 30, "Forecast curve length is not 30 days"
    assert curve[0]["projected_daily_demand"] > 0, "Day 1 forecast demand must be > 0"
    
    # Day 6 weekend multiplier check (1.25x of 4.0 = 5.0)
    assert curve[5]["projected_daily_demand"] == 5.0, f"Weekend multiplier failed: expected 5.0 got {curve[5]['projected_daily_demand']}"
    print(f"✅ 30-day curve generated cleanly. Day 1 demand: {curve[0]['projected_daily_demand']}, Weekend Day 6 demand: {curve[5]['projected_daily_demand']}")

def test_statistical_safety_stock():
    print("--- 2. Testing Statistical Safety Stock & Risk Timelines ---")
    ss = calculate_statistical_safety_stock(avg_daily_sales=10.0, lead_time_days=4)
    assert ss >= 1, "Safety stock calculation failed"
    print(f"✅ Statistical Safety Stock (Velocity=10, LeadTime=4d, Z=1.65): {ss} units")
    
    product_critical = {
        "barcode": "CRIT-01",
        "name": "Critical Item",
        "stock": 3,
        "sales_velocity": 5.0,
        "lead_time_days": 4,
        "selling_price": 50.0
    }
    risk = calculate_stockout_risk_timeline(product_critical)
    assert risk["risk_level"] == "CRITICAL", f"Expected CRITICAL risk level, got {risk['risk_level']}"
    assert risk["revenue_at_risk"] > 0, "Revenue at risk calculation failed"
    print(f"✅ Risk timeline OK: {risk['risk_level']} | Revenue at Risk: ${risk['revenue_at_risk']}")

def test_abc_classification():
    print("--- 3. Testing ABC Inventory Categorization ---")
    products = [
        {"barcode": "1", "name": "High Val", "sales_velocity": 100, "selling_price": 500},
        {"barcode": "2", "name": "Mid Val", "sales_velocity": 10, "selling_price": 50},
        {"barcode": "3", "name": "Low Val", "sales_velocity": 1, "selling_price": 5}
    ]
    abc = perform_abc_analysis(products)
    assert len(abc["A"]) >= 1, "Category A empty"
    print(f"✅ ABC Classification Summary: A={len(abc['A'])}, B={len(abc['B'])}, C={len(abc['C'])}")

def test_ml_rest_endpoints():
    print("--- 4. Testing FastAPI ML Endpoints ---")
    from fastapi.testclient import TestClient
    from main import app
    
    client = TestClient(app)
    
    resp_fc = client.get("/api/agent/forecast")
    assert resp_fc.status_code == 200
    fc_body = resp_fc.json()
    assert "forecasts" in fc_body
    print(f"✅ GET /api/agent/forecast returned {len(fc_body['forecasts'])} item forecasts")
    
    resp_ss = client.get("/api/agent/safety_stock")
    assert resp_ss.status_code == 200
    ss_body = resp_ss.json()
    assert "recommendations" in ss_body
    assert "abc_analysis_summary" in ss_body
    print(f"✅ GET /api/agent/safety_stock returned {len(ss_body['recommendations'])} safety stock items")

if __name__ == "__main__":
    test_30day_forecast()
    test_statistical_safety_stock()
    test_abc_classification()
    test_ml_rest_endpoints()
    print("\n🎉 ALL PHASE 3 PREDICTIVE ML TESTS PASSED SUCCESSFULLY!")
