"""Answers must come from the caller's own workspace — nothing else.

Every assistant answer is built from an `InventoryFacts` snapshot, and every
snapshot is keyed by company. This proves the property end to end rather than
by inspection: two workspaces with deliberately different catalogs ask the same
questions in the same process, and neither ever sees the other's products.

The paths that could break it are all covered: the fact store, the answer cache
(a shared key would serve one tenant's numbers to another), the pending-action
store (a confirm landing on someone else's preview), and the bulk selectors,
which resolve a whole product set rather than one named item.
"""

import sys

sys.path.insert(0, ".")

import testkit  # sets OFFLINE_MODE

from fastapi.testclient import TestClient

import auth
import bulk
import deterministic
import main
from facts import fact_store
from pending import pending_actions

ACME = "acme_co"
RIVAL = "rival_co"

ACME_PRODUCTS = [
    {"id": "a1", "barcode": "ACME-1", "name": "Acme Cannula 18G", "stock": 4,
     "min_threshold": 40, "category": "Medical", "cost_price": 2.0, "selling_price": 5.0},
    {"id": "a2", "barcode": "ACME-2", "name": "Acme Gauze Roll", "stock": 900,
     "min_threshold": 50, "category": "Medical", "cost_price": 1.0, "selling_price": 3.0},
]
RIVAL_PRODUCTS = [
    {"id": "r1", "barcode": "RIVAL-1", "name": "Rival Espresso Beans", "stock": 2,
     "min_threshold": 30, "category": "Beverages", "cost_price": 9.0, "selling_price": 20.0},
]

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def excludes(label, haystack, needle):
    ok = needle.lower() not in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} leaked into the answer")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def contains(label, haystack, needle):
    ok = needle.lower() in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} missing")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


client = TestClient(main.app)


def as_user(uid, company_id):
    """Install a verified principal, the way the auth dependency would."""
    principal = auth.Principal(uid=uid, company_id=company_id)
    main.app.dependency_overrides[auth.verified_principal_rate_limited] = lambda: principal
    return principal


def ask(question, uid, company_id, session_id=None):
    as_user(uid, company_id)
    body = {"question": question, "company_id": company_id}
    if session_id:
        body["session_id"] = session_id
    response = client.post("/api/chat", json=body)
    assert response.status_code == 200, (response.status_code, response.text[:300])
    return response.json()


testkit.seed(ACME_PRODUCTS, company_id=ACME)
testkit.seed(RIVAL_PRODUCTS, company_id=RIVAL)
main.answer_cache.clear(ACME)
main.answer_cache.clear(RIVAL)


print("\n== Each workspace sees only its own catalog ==")
acme = ask("what is low stock", "u_acme", ACME)
rival = ask("what is low stock", "u_rival", RIVAL)

contains("acme sees its own product", acme["answer"], "Acme Cannula")
excludes("acme never sees the other tenant", acme["answer"], "Rival")
excludes("nor its barcodes", acme["answer"], "RIVAL-1")
contains("rival sees its own product", rival["answer"], "Rival Espresso")
excludes("rival never sees the other tenant", rival["answer"], "Acme")
check(
    "and the item rows are scoped too",
    [i["barcode"] for i in rival["items"]],
    ["RIVAL-1"],
)


print("\n== The answer cache is keyed per workspace ==")
# Same question, same wording, same process. A shared key would hand the second
# caller the first caller's numbers.
again_acme = ask("what is low stock", "u_acme", ACME)
again_rival = ask("what is low stock", "u_rival", RIVAL)
contains("acme still gets acme", again_acme["answer"], "Acme Cannula")
excludes("even from cache", again_acme["answer"], "Rival")
contains("rival still gets rival", again_rival["answer"], "Rival Espresso")
excludes("even from cache", again_rival["answer"], "Acme")


print("\n== A bulk selector resolves against the caller's own products ==")
acme_bulk = ask("add 10 units to all low stock items", "u_acme", ACME, "s_acme")
rival_bulk = ask("add 10 units to all low stock items", "u_rival", RIVAL, "s_rival")

check(
    "acme's targets are acme's",
    sorted(t["barcode"] for t in acme_bulk["pending_action"]["targets"]),
    ["ACME-1"],
)
check(
    "rival's targets are rival's",
    sorted(t["barcode"] for t in rival_bulk["pending_action"]["targets"]),
    ["RIVAL-1"],
)
excludes("no cross-tenant product in the preview", acme_bulk["answer"], "Espresso")


print("\n== A confirm cannot reach another workspace's pending action ==")
# Both previews are live at once. Confirming in one must not touch the other.
confirmed = ask("confirm", "u_acme", ACME, "s_acme")
check("acme's own change applied", confirmed["executed_actions"][0]["result"]["applied"], 1)

acme_after = fact_store.get(ACME, force=True)
rival_after = fact_store.get(RIVAL, force=True)
check("acme's stock moved", acme_after.by_barcode("ACME-1").quantity, 14)
check("rival's stock did not", rival_after.by_barcode("RIVAL-1").quantity, 2)
check("rival's preview is still pending", pending_actions.get(RIVAL, "s_rival") is not None, True)

# ...and a same-named session in the other workspace is a different slot.
check("acme's slot is now empty", pending_actions.get(ACME, "s_acme"), None)
pending_actions.clear(RIVAL, "s_rival")


print("\n== Two people in one workspace don't share a pending action ==")
# The session id used to default to the *company* id, so two members who sent
# none shared a slot: one could confirm a change the other had previewed, and
# it would run under the confirmer's permissions.
testkit.seed(ACME_PRODUCTS, company_id=ACME)
main.answer_cache.clear(ACME)

first = ask("deduct 3 units from all products", "u_one", ACME)
check("the preview is armed", first["pending_action"]["tool"], "__bulk__")

# A second member, no session id, says "confirm" out of the blue.
second = ask("confirm", "u_two", ACME)
check("it did not execute for them", second.get("executed_actions"), [])
after = fact_store.get(ACME, force=True)
check("nothing was deducted", after.by_barcode("ACME-2").quantity, 900)

# The person who asked for it can still confirm their own.
mine = ask("confirm", "u_one", ACME)
check("the original caller still can", mine["executed_actions"][0]["result"]["applied"], 2)
pending_actions.clear(ACME, "uid:u_one")


print("\n== The fact layer itself keeps the two apart ==")
check("acme catalog size", len(fact_store.get(ACME).products), 2)
check("rival catalog size", len(fact_store.get(RIVAL).products), 1)
check(
    "selectors read only the snapshot they are given",
    [p.barcode for p in bulk._low(fact_store.get(RIVAL))],
    ["RIVAL-1"],
)
check(
    "so does the setup overview",
    "Acme" in deterministic._setup_overview(fact_store.get(RIVAL)),
    False,
)


print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(" -", f)
    sys.exit(1)
print("All tenant isolation tests passed.")
