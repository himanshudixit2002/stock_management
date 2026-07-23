import os
import sys

# Add rag_backend directory to python path
sys.path.insert(0, os.path.dirname(__file__))

from inventory_db import db_instance
from graph import rag_pipeline

def test_inventory_db_mutations():
    print("--- 1. Testing Inventory DB Atomic Mutations ---")
    # Reset / seed
    db_instance._seed_default_data()

    # Test update stock
    res1 = db_instance.update_stock("89010001", 25, "Restock batch")
    print("Stock update res:", res1["success"], "| New Stock:", res1.get("new_stock"))
    assert res1["success"] == True
    assert res1["new_stock"] == 40

    # Test PO creation
    res2 = db_instance.create_purchase_order("89010004", 50, "Dairy Supplier")
    print("PO creation res:", res2["success"], "| PO ID:", res2.get("po_id"))
    assert res2["success"] == True

    # Test Autopilot scan
    recs = db_instance.run_autopilot_scan()
    print("Autopilot recommendations count:", len(recs))
    assert len(recs) > 0
    print("Sample recommendation:", recs[0])

def test_pipeline_action_routing():
    print("\n--- 2. Testing LangGraph Agent Pipeline Routing ---")
    
    # Action Query
    state_action = rag_pipeline.invoke({"question": "Add 30 units to Fresh Apples barcode 89010001"})
    print("\nAction Query Output:")
    print("Intent:", state_action.get("intent"))
    print("Generation:\n", state_action.get("generation"))
    print("Executed Actions:", state_action.get("executed_actions"))
    assert state_action.get("intent") == "ACTION"
    assert len(state_action.get("executed_actions", [])) > 0

    # Analytics Query
    state_analytics = rag_pipeline.invoke({"question": "Provide a full stock summary report and financial valuation"})
    print("\nAnalytics Query Output:")
    print("Intent:", state_analytics.get("intent"))
    print("Generation:\n", state_analytics.get("generation"))
    assert state_analytics.get("intent") == "ANALYTICS"

    print("\n✅ ALL TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_inventory_db_mutations()
    test_pipeline_action_routing()
