"""Answer-cache tests.

The behaviour that matters: a hit is fast, and a hit is impossible once the
inventory has moved. The old cache achieved neither — it keyed on chat history
(so it never hit) and nothing rotated the key when stock changed in the app.
"""

import os
import sys
import time

sys.path.insert(0, ".")

TEST_DB = os.path.join(os.path.dirname(__file__), "test_cache.db")
os.environ["CACHE_DB_PATH"] = TEST_DB
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)

from cache import AnswerCache, normalize_question

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


cache = AnswerCache(db_path=TEST_DB)
CID = "acme"
FP_A = "fingerprint_aaa"
FP_B = "fingerprint_bbb"
PAYLOAD = {"answer": "You have 42 widgets.", "intent": "ANALYTICS"}

print("\n== Miss, then hit ==")
check("cold miss", cache.get("how many widgets", CID, FP_A), None)
cache.set("how many widgets", CID, FP_A, PAYLOAD)
check("warm hit", cache.get("how many widgets", CID, FP_A), PAYLOAD)

print("\n== Hits survive punctuation and casing, unlike an exact hash ==")
check("case/punctuation insensitive", cache.get("How many widgets?", CID, FP_A), PAYLOAD)
check("normalisation", normalize_question("  How MANY  widgets?? "), "how many widgets")

print("\n== A stock change makes the cached answer unreachable ==")
check("different fingerprint misses", cache.get("how many widgets", CID, FP_B), None)

print("\n== Tenants are isolated ==")
check("other company misses", cache.get("how many widgets", "other_co", FP_A), None)

print("\n== Business type is part of the key ==")
check("other business type misses", cache.get("how many widgets", CID, FP_A, "pharmacy"), None)

print("\n== Mutations are never cached ==")
cache.set("add 50 widgets", CID, FP_A, {"answer": "Done.", "intent": "EXECUTION"})
check("EXECUTION not stored", cache.get("add 50 widgets", CID, FP_A), None)
cache.set("empty", CID, FP_A, {"answer": "", "intent": "KNOWLEDGE"})
check("empty answer not stored", cache.get("empty", CID, FP_A), None)

print("\n== Scoped clear leaves other tenants alone ==")
cache.set("shared question", CID, FP_A, PAYLOAD)
cache.set("shared question", "other_co", FP_A, PAYLOAD)
cache.clear(CID)
check("cleared company misses", cache.get("shared question", CID, FP_A), None)
check("other company still hits", cache.get("shared question", "other_co", FP_A), PAYLOAD)

print("\n== TTL expiry ==")
short = AnswerCache(db_path=TEST_DB, ttl_seconds=0.2)
short.set("ttl probe", CID, FP_A, PAYLOAD)
check("fresh hit", short.get("ttl probe", CID, FP_A), PAYLOAD)
time.sleep(0.3)
check("expired miss", short.get("ttl probe", CID, FP_A), None)

print("\n== Session-bound answers are never cached ==")
# A preview parks a pending action against the session. Replaying it from cache
# reproduces the card with nothing behind it, so Confirm does nothing — and a
# replayed "Cancelled" leaves the real action live for a later confirm to apply.
import main

check(
    "a single-product preview",
    main._cacheable({"response_kind": "preview", "pending_action": {"tool": "update_stock"}}),
    False,
)
check(
    "a bulk preview",
    main._cacheable({"response_kind": "bulk_preview", "pending_action": {"tool": "__bulk__"}}),
    False,
)
check(
    "an ambiguity question",
    main._cacheable({"response_kind": "clarification"}),
    False,
)
check("an ordinary report", main._cacheable({"response_kind": "report"}), True)
check("a confirmation bypasses the cache", main._bypass_cache("confirm"), True)
check("so does a cancellation", main._bypass_cache("Cancel"), True)
check("an ordinary question does not", main._bypass_cache("what is low stock"), False)

print("\n== Hit rate is tracked ==")
stats = cache.stats()
ok = stats["hits"] > 0 and stats["misses"] > 0
if not ok:
    _failures.append("hit/miss counters not tracking")
print(f"  {'PASS' if ok else 'FAIL'}  stats: {stats['hits']} hits, {stats['misses']} misses, {stats['hit_rate_pct']}%")

if os.path.exists(TEST_DB):
    os.remove(TEST_DB)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All cache tests passed.")
