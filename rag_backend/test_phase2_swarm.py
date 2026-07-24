import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from agent_swarm import AutonomousSwarm
from inventory_db import db_instance

def test_swarm_autopilot_sweep():
    print("--- 1. Testing Swarm Autopilot Sweep ---")
    swarm = AutonomousSwarm(db=db_instance)
    
    # Ingest a low stock item needing reorder
    db_instance.upsert_product({
        "barcode": "TEST-SKU-99",
        "name": "Autonomous Test Widget",
        "stock": 2,
        "min_threshold": 15,
        "cost_price": 50.0,
        "selling_price": 100.0,
        "sales_velocity": 5,
        "lead_time_days": 3
    })
    
    # Ingest a dead stock item needing clearance
    db_instance.upsert_product({
        "barcode": "DEAD-SKU-01",
        "name": "Dead Stock Gadget",
        "stock": 40,
        "min_threshold": 5,
        "cost_price": 10.0,
        "selling_price": 30.0,
        "sales_velocity": 0,
        "lead_time_days": 7
    })
    
    # Ingest a low margin supplier item
    db_instance.upsert_product({
        "barcode": "MARGIN-SKU-02",
        "name": "Low Margin Cable",
        "stock": 100,
        "min_threshold": 10,
        "cost_price": 95.0,
        "selling_price": 100.0,
        "sales_velocity": 2,
        "lead_time_days": 2
    })
    
    sweep_results = swarm.run_full_autopilot_sweep()
    
    assert len(sweep_results["reorders_processed"]) >= 1, "Reorder agent failed to pick up low stock SKU"
    assert len(sweep_results["clearance_recommendations"]) >= 1, "Decay agent failed to pick up dead stock SKU"
    assert len(sweep_results["supplier_alerts"]) >= 1, "Supplier watch agent failed to flag low margin SKU"
    
    print(f"✅ Reorders Processed: {len(sweep_results['reorders_processed'])}")
    print(f"✅ Clearance Recommendations: {len(sweep_results['clearance_recommendations'])}")
    print(f"✅ Supplier Alerts: {len(sweep_results['supplier_alerts'])}")

def test_po_approval_workflow():
    print("--- 2. Testing 1-Click PO Approval Workflow ---")
    swarm = AutonomousSwarm(db=db_instance)
    
    # Force a high-cost reorder item ($500 x 50 = $25,000) exceeding $1,000 spend cap
    db_instance.upsert_product({
        "barcode": "EXPENSIVE-SKU-100",
        "name": "High Value Industrial Server",
        "stock": 1,
        "min_threshold": 10,
        "cost_price": 500.0,
        "selling_price": 1000.0,
        "sales_velocity": 2,
        "lead_time_days": 5
    })
    
    sweep_res = swarm.run_full_autopilot_sweep()
    assert len(swarm.pending_pos) >= 1, "High cost PO was not queued for approval"
    
    po_id = list(swarm.pending_pos.keys())[0]
    print(f"✅ PO Queued for Approval: {po_id} (Details: {swarm.pending_pos[po_id]})")
    
    # Test approval
    approval_res = swarm.approve_pending_po(po_id)
    assert approval_res["status"] == "APPROVED", "PO approval failed"
    assert po_id not in swarm.pending_pos, "PO remained in pending queue after approval"
    print(f"✅ PO Approved successfully: {approval_res['message']}")

def test_swarm_rest_endpoints():
    print("--- 3. Testing Swarm REST API Endpoints ---")
    from fastapi.testclient import TestClient
    from main import app
    
    client = TestClient(app)
    
    # 1. Trigger Autopilot POST
    resp_ap = client.post("/api/swarm/autopilot")
    assert resp_ap.status_code == 200
    ap_body = resp_ap.json()
    assert ap_body["status"] == "success"
    print(f"✅ POST /api/swarm/autopilot returned: {ap_body['status']}")
    
    # 2. Get Swarm Logs GET
    resp_logs = client.get("/api/swarm/logs")
    assert resp_logs.status_code == 200
    log_body = resp_logs.json()
    assert "episodic_memory" in log_body
    print(f"✅ GET /api/swarm/logs returned {len(log_body['episodic_memory'])} entries")

if __name__ == "__main__":
    test_swarm_autopilot_sweep()
    test_po_approval_workflow()
    test_swarm_rest_endpoints()
    print("\n🎉 ALL PHASE 2 SWARM TESTS PASSED SUCCESSFULLY!")
