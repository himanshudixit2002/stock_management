import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from inventory_db import db_instance

def test_voice_command_parsing():
    print("--- 1. Testing Voice AI Command Parsing ---")
    
    # 1. Voice Deduction
    res_deduct = db_instance.process_voice_command("Deduct 10 units of Fresh Apples damaged")
    assert res_deduct["status"] == "success", "Voice deduction failed"
    assert "audio_response_text" in res_deduct, "Audio response missing"
    assert "Deducted 10 units" in res_deduct["audio_response_text"]
    print(f"✅ Voice Deduction Audio Response: '{res_deduct['audio_response_text']}'")
    
    # 2. Voice Addition
    res_add = db_instance.process_voice_command("Add 25 units of Pro Laptops received")
    assert res_add["status"] == "success", "Voice addition failed"
    assert "Added 25 units" in res_add["audio_response_text"]
    print(f"✅ Voice Addition Audio Response: '{res_add['audio_response_text']}'")
    
    # 3. Voice Physical Audit Count
    res_audit = db_instance.process_voice_command("Audit Sparkling Water count 150")
    assert res_audit["status"] == "success", "Voice audit failed"
    assert "150 units" in res_audit["audio_response_text"]
    print(f"✅ Voice Audit Audio Response: '{res_audit['audio_response_text']}'")

def test_visual_camera_audit():
    print("--- 2. Testing Multi-Item Camera Visual Audit ---")
    detected = [
        {"name": "Fresh Apples", "count": 12},
        {"name": "Pro Laptops", "count": 120}
    ]
    summary = db_instance.process_visual_audit_photo(detected)
    assert summary["audited_items_count"] == 2, "Visual audit count mismatch"
    assert summary["results"][0]["visual_counted_stock"] == 12
    print(f"✅ Visual Audit Processed {summary['audited_items_count']} items with discrepancy logs")

def test_multimodal_rest_endpoints():
    print("--- 3. Testing FastAPI Multi-Modal REST Endpoints ---")
    from fastapi.testclient import TestClient
    from main import app
    
    client = TestClient(app)
    
    # Voice command REST endpoint
    resp_v = client.post("/api/agent/voice_command", json={"speech_text": "Deduct 5 boxes of Fresh Apples"})
    assert resp_v.status_code == 200
    v_body = resp_v.json()
    assert v_body["status"] == "success"
    assert "audio_response_text" in v_body
    print(f"✅ POST /api/agent/voice_command returned: '{v_body['audio_response_text']}'")
    
    # Visual audit REST endpoint
    resp_cam = client.post("/api/agent/visual_audit", json={
        "detected_items": [
            {"name": "Fresh Apples", "count": 10}
        ]
    })
    assert resp_cam.status_code == 200
    cam_body = resp_cam.json()
    assert cam_body["status"] == "success"
    print(f"✅ POST /api/agent/visual_audit returned: {cam_body['status']}")

if __name__ == "__main__":
    test_voice_command_parsing()
    test_visual_camera_audit()
    test_multimodal_rest_endpoints()
    print("\n🎉 ALL PHASE 4 MULTI-MODAL TESTS PASSED SUCCESSFULLY!")
