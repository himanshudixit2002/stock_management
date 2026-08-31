from fastapi.testclient import TestClient
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import testkit
from main import app

client = TestClient(app)
testkit.seed()
H = testkit.headers()

def test_endpoints():
    print("--- Testing FastAPI Endpoints ---")
    
    # 1. Health Check
    res = client.get("/health")
    assert res.status_code == 200
    print("Health Check:", res.json())

    # 2. Get Inventory
    res = client.get("/api/inventory", headers=H)
    assert res.status_code == 200
    print("Inventory Count:", len(res.json()["products"]))

    # 3. Autopilot Scan
    res = client.get("/api/agent/autopilot", headers=H)
    assert res.status_code == 200
    print("Autopilot Scan Recommendations:", len(res.json()["recommendations"]))

    # 4. Ingest sample product & Chat Endpoint (Action Query)
    client.post("/api/ingest", headers=H, json={"products": [{
        "name": "Sparkling Water (Pack of 12)",
        "barcode": "89010003",
        "stock": 200,
        "min_threshold": 100,
        "category": "Beverages",
        "cost_price": 4.0,
        "selling_price": 8.99
    }]})
    
    res = client.post("/api/chat", headers=H, json={"question": "Add 15 units to barcode 89010003"})
    assert res.status_code == 200
    chat_res = res.json()
    print("Chat API Action Response Intent:", chat_res["intent"])
    print("Answer:\n", chat_res["answer"])
    assert chat_res["intent"] in ["EXECUTION", "ANALYTICS", "KNOWLEDGE"]
    # A mutation must be previewed, never applied straight off a single message.
    assert not chat_res["executed_actions"], "stock was mutated without confirmation"

    # 6. Stream Chat Endpoint
    print("Testing /api/chat/stream endpoint...")
    res = client.post("/api/chat/stream", headers=H, json={"question": "Add 5 units to barcode 89010003"})
    assert res.status_code == 200
    assert "text/event-stream" in res.headers["content-type"]
    assert "data:" in res.text
    print("✓ /api/chat/stream event stream verified!")

    # 7. Test Autonomous Swarm Endpoints
    res = client.post("/api/swarm/trigger", headers=H, json={"event_name": "LOW_STOCK_TRIGGER", "payload": {"barcode": "89010001"}})
    assert res.status_code == 200
    print("Swarm Trigger Status:", res.json()["status"])

    res = client.post("/api/swarm/query", headers=H, json={"query": "Show me low stock items"})
    assert res.status_code == 200
    print("Swarm Query Type:", res.json()["result"]["type"])

    res = client.post("/api/guardrails/validate", headers=H, json={"action_type": "update_stock", "payload": {"new_stock": -10}})
    assert res.status_code == 200
    assert res.json()["passed"] is False
    print("Guardrails Rejection Verified!")

    # A request that cannot name its workspace must be refused outright. Serving
    # it from a shared fallback is what showed one tenant another's inventory.
    assert client.get("/api/inventory").status_code == 400
    assert client.post("/api/chat", json={"question": "show all products"}).status_code == 400
    assert client.get("/api/agent/forecast").status_code == 400
    print("Company id is required on every data endpoint ✓")

    print("\n✅ ALL API & SWARM ENDPOINTS VERIFIED SUCCESSFULLY!")

if __name__ == "__main__":
    test_endpoints()

