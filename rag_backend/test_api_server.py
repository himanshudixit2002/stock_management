from fastapi.testclient import TestClient
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from main import app

client = TestClient(app)

def test_endpoints():
    print("--- Testing FastAPI Endpoints ---")
    
    # 1. Health Check
    res = client.get("/health")
    assert res.status_code == 200
    print("Health Check:", res.json())

    # 2. Get Inventory
    res = client.get("/api/inventory")
    assert res.status_code == 200
    print("Inventory Count:", len(res.json()["products"]))

    # 3. Autopilot Scan
    res = client.get("/api/agent/autopilot")
    assert res.status_code == 200
    print("Autopilot Scan Recommendations:", len(res.json()["recommendations"]))

    # 4. Chat Endpoint (Action Query)
    res = client.post("/api/chat", json={"question": "Add 15 units to product barcode 89010003"})
    assert res.status_code == 200
    chat_res = res.json()
    print("Chat API Action Response Intent:", chat_res["intent"])
    print("Answer:\n", chat_res["answer"])
    assert chat_res["intent"] == "ACTION"
    assert len(chat_res["executed_actions"]) > 0

    # 5. Ledger endpoint
    res = client.get("/api/inventory/ledger")
    assert res.status_code == 200
    print("Ledger Action Count:", len(res.json()["action_ledger"]))

    print("\n✅ API ENDPOINTS VERIFIED SUCCESSFULLY!")

if __name__ == "__main__":
    test_endpoints()
