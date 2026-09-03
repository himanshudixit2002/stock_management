"""Bulk requests over the real HTTP surface — no LLM, no Firestore.

`test_bulk.py` drives the graph nodes directly. This covers what the app
actually talks to: the JSON shape, the SSE frames, and the fact that a preview
is *not* cached (replaying one from cache would show a confirmation card with
no action behind it).
"""

import json
import sys

sys.path.insert(0, ".")

import testkit  # sets OFFLINE_MODE

from fastapi.testclient import TestClient

import auth
import main
from facts import fact_store
from pending import pending_actions

CID = testkit.TEST_COMPANY
SID = "api_session"

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def contains(label, haystack, needle):
    ok = needle.lower() in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} missing")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


principal = auth.Principal(uid="u1", company_id=CID)
main.app.dependency_overrides[auth.verified_principal_rate_limited] = lambda: principal
client = TestClient(main.app)


def ask(question):
    response = client.post(
        "/api/chat",
        json={"question": question, "session_id": SID, "company_id": CID},
    )
    assert response.status_code == 200, (response.status_code, response.text[:400])
    return response.json()


def stream(question):
    """Drain the SSE endpoint into its frames."""
    with client.stream(
        "POST",
        "/api/chat/stream",
        json={"question": question, "session_id": SID, "company_id": CID},
    ) as response:
        assert response.status_code == 200, response.status_code
        frames = []
        for line in response.iter_lines():
            line = line if isinstance(line, str) else line.decode()
            if line.startswith("data: "):
                frames.append(json.loads(line[6:]))
    return frames


print("\n== A bulk request previews over HTTP, then applies ==")
pending_actions.clear(CID, SID)
main.answer_cache.clear(CID)
testkit.seed()

preview = ask("add 10 pieces for all low stock")
check("declared as a bulk preview", preview["response_kind"], "bulk_preview")
check("no model was called", preview["answered_by"], "deterministic")
check("the pending action is bulk", preview["pending_action"]["tool"], "__bulk__")
check("both low products", preview["pending_action"]["count"], 2)
check(
    "the client gets the rows",
    [(i["name"], i["change"]) for i in preview["items"]],
    [("Fresh Apples (kg)", 10), ("Organic Whole Milk 1L", 10)],
)
contains("and the products are named", preview["answer"], "Fresh Apples")

applied = ask("confirm")
check("executed", applied["response_kind"], "executed")
record = applied["executed_actions"][0]
check("one bulk record", record["tool"], "bulk_update_stock")
check("two writes", record["result"]["applied"], 2)
check("no failures", record["result"]["failed"], 0)
check("the catalog is echoed back", isinstance(applied["updated_catalog"], list), True)

after = fact_store.get(CID, force=True)
check("apples applied", after.by_barcode("89010001").quantity, 25)
check("milk applied", after.by_barcode("89010004").quantity, 18)


print("\n== A preview is never served from cache ==")
# Cached, it would replay the confirmation card with no action behind it, and
# Confirm would silently do nothing.
pending_actions.clear(CID, SID)
testkit.seed()
first = ask("add 5 units to all low stock items")
pending_actions.clear(CID, SID)
second = ask("add 5 units to all low stock items")
check("first was computed", first["answered_by"], "deterministic")
check("second was too, not cached", second["answered_by"], "deterministic")
check("and it re-armed the action", second["pending_action"]["tool"], "__bulk__")


print("\n== A cancellation is never served from cache either ==")
pending_actions.clear(CID, SID)
testkit.seed()
ask("add 5 units to all low stock items")
cancelled = ask("cancel")
check("cancelled", cancelled["answered_by"], "pending")
check("nothing pending", pending_actions.get(CID, SID), None)

# Re-arm, then cancel again with the same wording: a cached "Cancelled" would
# leave this action live for a later confirm to apply.
ask("add 5 units to all low stock items")
again = ask("cancel")
check("cancelled again, for real", again["answered_by"], "pending")
check("still nothing pending", pending_actions.get(CID, SID), None)


print("\n== The streaming endpoint carries the same structure ==")
pending_actions.clear(CID, SID)
main.answer_cache.clear(CID)
testkit.seed()
frames = stream("add 10 units to all low stock items")
done = [f for f in frames if f.get("type") == "done"]
check("exactly one done frame", len(done), 1)
check("kind survives", done[0]["response_kind"], "bulk_preview")
check("pending action survives", done[0]["pending_action"]["tool"], "__bulk__")
check("items survive", len(done[0]["items"]), 2)
deltas = "".join(f.get("content", "") for f in frames if f.get("type") == "delta")
contains("the preview was streamed as text", deltas, "Confirm bulk change")


print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(" -", f)
    sys.exit(1)
print("All bulk API tests passed.")
