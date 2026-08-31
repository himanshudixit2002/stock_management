"""Product creation and location-aware stock moves.

Adding a product needs more than a name: the app filters by location and
category, so a product created with a made-up shelf is one the user cannot find
afterwards. These assert that missing or unrecognised values produce a question
rather than a confident guess.
"""

import sys

import testkit
from facts import InventoryFacts, derive_product_fact, fact_store
from nodes import _vet_new_product

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def says(label, text, needle):
    ok = needle.lower() in (text or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} missing from {text[:80]!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


facts = testkit.seed()
facts.configured_locations = ["Rack A2", "Shelf 1", "Cold Store"]
facts.categories = [{"id": "c1", "name": "Ointment"}, {"id": "c2", "name": "Surgical"}]

print("\n== Required fields are asked for, never invented ==")
msg, ready = _vet_new_product({}, facts)
check("no name -> not ready", ready, False)
says("asks for a name", msg, "called")

msg, ready = _vet_new_product({"name": "Gauze Swabs 5cm"}, facts)
check("no quantity -> not ready", ready, False)
says("asks how many", msg, "how many")

msg, ready = _vet_new_product({"name": "Gauze Swabs 5cm", "quantity": 40}, facts)
check("no location -> not ready", ready, False)
says("asks where", msg, "where")
says("offers the real locations", msg, "Rack A2")

print("\n== Made-up locations and categories are rejected ==")
msg, ready = _vet_new_product(
    {"name": "Gauze Swabs 5cm", "quantity": 40, "location": "Aisle 9"}, facts
)
check("unknown location -> not ready", ready, False)
says("names the offender", msg, "Aisle 9")
says("lists the valid ones", msg, "Shelf 1")

msg, ready = _vet_new_product(
    {"name": "Gauze Swabs 5cm", "quantity": 40, "location": "Shelf 1",
     "category_name": "Widgets"}, facts
)
check("unknown category -> not ready", ready, False)
says("lists real categories", msg, "Ointment")

print("\n== A complete product previews, with values snapped to the catalog ==")
args = {"name": "Gauze Swabs 5cm", "quantity": 40, "location": "shelf 1",
        "category_name": "surgical", "cost_price": 12.5, "selling_price": 20.0,
        "unit": "box", "brand": "Acme", "size": "Pack of 10"}
msg, ready = _vet_new_product(args, facts)
check("ready to preview", ready, True)
check("location snapped to real casing", args["location"], "Shelf 1")
check("category snapped to real casing", args["category_name"], "Surgical")
check("category id resolved", args["category_id"], "c2")
says("preview shows the quantity", msg, "40")
says("preview shows the location", msg, "Shelf 1")
says("preview asks to confirm", msg, "confirm")

print("\n== Blank optional fields are disclosed, not hidden ==")
args2 = {"name": "Cotton Buds", "quantity": 5, "location": "Shelf 1"}
msg, ready = _vet_new_product(args2, facts)
check("still ready", ready, True)
says("says what was left blank", msg, "left blank")
says("mentions the missing price", msg, "price")

print("\n== Creating a near-duplicate is challenged ==")
msg, ready = _vet_new_product(
    {"name": "Fresh Apples (kg)", "quantity": 10, "location": "Shelf 1"}, facts
)
check("duplicate -> not ready", ready, False)
says("points at the existing product", msg, "already in your catalog")


# --- Field extraction across turns -----------------------------------------
from nodes import _extract_product_fields, _NEW_PRODUCT_RE  # noqa: E402

print("\n== An unrecognised location is named back, not silently re-asked ==")
d = _extract_product_fields("put them in Aisle 99", facts, have_name=True)
check("no location invented", d.get("location"), None)
check("the attempt is remembered", d.get("_location_guess"), "Aisle 99")
msg, ready = _vet_new_product(
    {"name": "Gauze", "quantity": 10, **d}, facts
)
check("not ready", ready, False)
says("names what was rejected", msg, "Aisle 99")
says("offers the real ones", msg, "Rack A2")

print("\n== The request is recognised as product creation ==")
for phrase in ["add a new product called Sterile Gloves Large",
               "create a product", "register new item", "add new sku"]:
    ok = bool(_NEW_PRODUCT_RE.search(phrase))
    if not ok:
        _failures.append(f"not recognised: {phrase}")
    print(f"  {'PASS' if ok else 'FAIL'}  {phrase!r}")

print("\n== Fields are gathered turn by turn ==")
d = _extract_product_fields("add a new product called Sterile Gloves Large", facts, have_name=False)
check("name from the first turn", d.get("name"), "Sterile Gloves Large")
d2 = _extract_product_fields("50 units", facts, have_name=True)
check("quantity from a bare answer", d2.get("quantity"), 50)
check("no name re-extracted once known", "name" in d2, False)
d3 = _extract_product_fields("put them in Rack A2", facts, have_name=True)
check("location matched to the company's own list", d3.get("location"), "Rack A2")
d4 = _extract_product_fields("cost price 12.50 and selling price 20", facts, have_name=True)
check("cost price", d4.get("cost_price"), 12.5)
check("selling price", d4.get("selling_price"), 20.0)
d5 = _extract_product_fields("it is a Surgical item, barcode 948673537211", facts, have_name=True)
check("category matched", d5.get("category_name"), "Surgical")
check("barcode picked up", d5.get("barcode"), "948673537211")

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All product-creation tests passed.")
