"""Voice and visual audit, now sharing the one product resolver.

Voice used to carry its own matcher (a fourth copy of that logic) which picked
the first product containing a spoken word. That is how "deduct 5 cannula" could
silently hit the wrong SKU. It now goes through `resolver.py` like everything
else: confident matches still execute hands-free, ambiguous ones ask.
"""

import sys

import testkit
from fastapi.testclient import TestClient

import voice
from facts import fact_store
from main import app

client = TestClient(app)
CO = testkit.TEST_COMPANY
H = testkit.headers()
_failures = []


def check(label, ok, detail=""):
    if not ok:
        _failures.append(f"{label} {detail}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  -- {detail}" if detail else ""))


def stock_of(barcode):
    return fact_store.get(CO, force=True).by_barcode(barcode).quantity


print("\n== Voice executes a confident match hands-free ==")
testkit.seed()
before = stock_of("89010001")
res = voice.process_voice_command("Deduct 10 units of Fresh Apples damaged", CO)
check("deduction succeeded", res["status"] == "success", res.get("audio_response_text", "")[:70])
check("stock moved down by 10", stock_of("89010001") == before - 10,
      f"{before} -> {stock_of('89010001')}")

testkit.seed()
before = stock_of("89010002")
res = voice.process_voice_command("Add 20 units of Pro Laptops received", CO)
check("addition succeeded", res["status"] == "success", res.get("audio_response_text", "")[:70])
check("stock moved up by 20", stock_of("89010002") == before + 20,
      f"{before} -> {stock_of('89010002')}")

print("\n== Voice asks instead of guessing between similar SKUs ==")
testkit.seed([
    {"id": "c18", "barcode": "1001", "name": "Cannula 18G", "stock": 100, "min_threshold": 10},
    {"id": "c20", "barcode": "1002", "name": "Cannula 20G", "stock": 100, "min_threshold": 10},
])
res = voice.process_voice_command("deduct 5 cannula", CO)
check("does not execute", res["status"] != "success", str(res.get("status")))
check("asks which one aloud",
      "18g" in res["audio_response_text"].lower() and "20g" in res["audio_response_text"].lower(),
      res["audio_response_text"][:90])
check("nothing was deducted", stock_of("1001") == 100 and stock_of("1002") == 100)

print("\n== Qualifying the request resolves it ==")
res = voice.process_voice_command("deduct 5 cannula 20g", CO)
check("executes", res["status"] == "success", res.get("audio_response_text", "")[:70])
check("hit the 20G", stock_of("1002") == 95, f"20G at {stock_of('1002')}")
check("left the 18G alone", stock_of("1001") == 100, f"18G at {stock_of('1001')}")

print("\n== Unknown products are refused ==")
res = voice.process_voice_command("add 5 zzz widget", CO)
check("refused", res["status"] != "success", res.get("audio_response_text", "")[:70])

print("\n== Visual audit ==")
testkit.seed()
res = client.post(
    "/api/agent/visual_audit",
    headers=H,
    json={"detected_items": [{"name": "Fresh Apples", "count": 12}]},
)
check("returns 200", res.status_code == 200, str(res.status_code))
summary = res.json().get("audit_summary", {})
check("audited one item", summary.get("audited_items_count") == 1)
row = (summary.get("results") or [{}])[0]
check("recorded the discrepancy", row.get("discrepancy") == 12 - 15, str(row.get("discrepancy")))
check("stock set to the counted quantity", stock_of("89010001") == 12,
      str(stock_of("89010001")))

print("\n== Endpoints still require a company id ==")
check("visual audit refused without one",
      client.post("/api/agent/visual_audit",
                  json={"detected_items": []}).status_code == 400)
check("voice command refused without one",
      client.post("/api/agent/voice_command",
                  json={"speech_text": "add 5 apples"}).status_code == 400)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All voice and visual audit tests passed.")
