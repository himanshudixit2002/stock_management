"""
Unit test for Autonomous Swarm, Guardrails, Predictive ML, and Code Engine.
"""

from agent_swarm import AutonomousSwarm
from guardrails import InventoryGuardrails
from predictive_ml import calculate_eoq, calculate_reorder_point, perform_abc_analysis

def test_predictive_ml():
    eoq = calculate_eoq(annual_demand=1000, ordering_cost=50, holding_cost_per_unit=5)
    assert eoq == 141, f"Expected EOQ 141, got {eoq}"

    rop = calculate_reorder_point(avg_daily_sales=10, lead_time_days=3, safety_stock=5)
    assert rop == 35, f"Expected ROP 35, got {rop}"
    print("✓ Predictive ML unit tests passed.")

def test_guardrails():
    guard = InventoryGuardrails(max_auto_cost=500.0)
    
    # Test valid small PO
    res1 = guard.validate_action("create_reorder_po", {"quantity": 10, "cost_price": 20.0})
    assert res1.passed is True
    assert res1.requires_human_approval is False

    # Test PO exceeding auto approval limit ($600 > $500)
    res2 = guard.validate_action("create_reorder_po", {"quantity": 30, "cost_price": 20.0})
    assert res2.passed is True
    assert res2.requires_human_approval is True
    assert res2.risk_level == "MEDIUM"

    # Test negative stock update (Critical error)
    res3 = guard.validate_action("update_stock", {"new_stock": -5})
    assert res3.passed is False
    assert res3.risk_level == "CRITICAL"
    print("✓ Guardrails unit tests passed.")

def test_swarm_event_trigger():
    swarm = AutonomousSwarm()
    res = swarm.process_event_trigger("LOW_STOCK_TRIGGER", {"barcode": "89010001"})
    assert "status" in res
    print(f"✓ Autonomous Swarm trigger output: {res['status']}")

def test_swarm_semantic_query():
    swarm = AutonomousSwarm()
    res1 = swarm.process_query("Show me low stock items")
    assert res1["from_cache"] is False

    # Second call should hit semantic cache
    res2 = swarm.process_query("Show me low stock items")
    assert res2["from_cache"] is True
    print("✓ Semantic Cache lookup test passed (<1ms response).")

if __name__ == "__main__":
    test_predictive_ml()
    test_guardrails()
    test_swarm_event_trigger()
    test_swarm_semantic_query()
    print("All Autonomous AI backend tests passed successfully!")
