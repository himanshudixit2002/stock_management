"""Packs: the assistant counts the way people do and writes the way the app does.

"Add 2 boxes" of a ten-to-a-box product used to add two pieces — the word
"boxes" only told the resolver the 2 was a quantity, never that it was ten
times bigger. These pin the conversion, and pin that it happens exactly once.
They also pin parity with the app: the same breakdown text and the same rule
precedence, so Settings and the assistant never disagree about a product.
"""

import sys
from datetime import datetime, timezone

sys.path.insert(0, ".")

import units
from facts import ProductFact, derive_product_fact
from nodes import _in_base_units


def tile(**overrides):
    fields = dict(
        id="p1",
        barcode="1001",
        name="Floor Tile 600x600",
        unit="pcs",
        pack_unit="box",
        units_per_pack=10,
        quantity=53,
    )
    fields.update(overrides)
    return ProductFact(**fields)


# --- words and numbers -------------------------------------------------------


def test_a_pack_word_is_its_unit_in_any_number_or_case():
    assert units.names_unit("boxes", "box")
    assert units.names_unit("Box", "box")
    assert units.names_unit("packs", "pack")
    assert not units.names_unit("pcs", "box")
    assert not units.names_unit("box", "")


def test_packs_said_reads_the_number_before_the_pack_word():
    assert units.packs_said("add 2 boxes of floor tile", "box") == 2
    assert units.packs_said("deduct 15 box from shelf A", "box") == 15
    assert units.packs_said("add 20 pcs of floor tile", "box") is None
    # A number in the product's name is not a count of packs.
    assert units.packs_said("add tiles 600x600", "box") is None


def test_breakdown_matches_the_app():
    # lib/utils/unit_conversion.dart formatQuantityWithUnits
    assert units.breakdown(23, "pcs", "box", 10) == "2 box 3 pcs"
    assert units.breakdown(20, "pcs", "box", 10) == "2 box"
    assert units.breakdown(3, "pcs", "box", 10) == "3 pcs"
    assert units.breakdown(23, "pcs", "box", 1) == "23 pcs"


# --- Settings › Unit conversions ---------------------------------------------


RULES = [
    {"id": "all", "packUnit": "box", "unitsPerPack": 2, "baseUnit": "pcs"},
    {"id": "tiles", "categoryId": "tiles", "packUnit": "box", "unitsPerPack": 3, "baseUnit": "pcs"},
    {"id": "kajaria", "company": "Kajaria", "packUnit": "box", "unitsPerPack": 4, "baseUnit": "pcs"},
    {"id": "big", "size": "600x600", "packUnit": "box", "unitsPerPack": 5, "baseUnit": "pcs"},
    {
        "id": "tiles-kajaria",
        "categoryId": "tiles",
        "company": "Kajaria",
        "packUnit": "box",
        "unitsPerPack": 6,
        "baseUnit": "pcs",
    },
]


def resolved(rules, **product):
    rule = units.resolve_rule(rules, **product)
    return rule and rule["id"]


def test_the_most_specific_rule_wins():
    attrs = dict(category_id="tiles", company="Kajaria", size="600x600")
    assert resolved(RULES, **attrs) == "tiles-kajaria"
    assert resolved(list(reversed(RULES)), **attrs) == "tiles-kajaria"


def test_equal_specificity_prefers_size_then_brand_then_category():
    attrs = dict(category_id="tiles", company="Kajaria", size="600x600")
    singles = [r for r in RULES if r["id"] in ("tiles", "kajaria", "big")]
    assert resolved(singles, **attrs) == "big"
    assert resolved([r for r in singles if r["id"] != "big"], **attrs) == "kajaria"


def test_brand_and_size_match_as_typed_by_people():
    assert resolved(RULES, category_id="x", company="kajaria ", size="") == "kajaria"
    assert resolved(RULES, category_id="paint", company="", size="") == "all"
    assert units.resolve_rule([], category_id="tiles") is None


def test_settings_entries_a_save_could_never_produce_are_dropped():
    rules = units.rules_from_settings(
        [
            RULES[1],
            "not a rule",
            {"id": "one", "packUnit": "box", "unitsPerPack": 1, "baseUnit": "pcs"},
            {"id": "same", "packUnit": "Box", "unitsPerPack": 5, "baseUnit": "box"},
            {"packUnit": "box", "unitsPerPack": 5, "baseUnit": "pcs"},
        ]
    )
    assert [r["id"] for r in rules] == ["tiles"]
    assert units.rules_from_settings(None) == []


def test_a_new_product_takes_its_rule_unless_it_names_another_unit():
    taken = units.units_for_new_product(RULES, "", category_id="tiles")
    assert taken == {"unit": "pcs", "baseUnit": "pcs", "packUnit": "box", "unitsPerPack": 3}
    kept = units.units_for_new_product(RULES, "kg", category_id="tiles")
    assert kept["baseUnit"] == "kg" and kept["unitsPerPack"] == 1
    plain = units.units_for_new_product([], "")
    assert plain == {"unit": "pcs", "baseUnit": "pcs", "packUnit": "box", "unitsPerPack": 1}


# --- the assistant ------------------------------------------------------------


def test_two_boxes_become_twenty_pieces():
    args = _in_base_units("update_stock", tile(), {"qty_change": 2}, "add 2 boxes of floor tile")
    assert args["qty_change"] == 20
    assert args["entered_as"] == "2 box = 20 pcs"


def test_a_deduction_keeps_its_sign():
    args = _in_base_units("update_stock", tile(), {"qty_change": -3}, "remove 3 boxes of floor tile")
    assert args["qty_change"] == -30


def test_a_model_that_already_multiplied_is_not_multiplied_again():
    args = {"qty_change": 20, "unit": "box"}
    assert _in_base_units("update_stock", tile(), args, "add 2 boxes of floor tile") == args


def test_the_unit_the_model_heard_converts_when_the_sentence_has_no_count():
    args = _in_base_units("update_stock", tile(), {"qty_change": 1, "unit": "box"}, "add a box of floor tile")
    assert args["qty_change"] == 10


def test_pieces_stay_pieces():
    args = {"qty_change": 2}
    assert _in_base_units("update_stock", tile(), args, "add 2 pcs of floor tile") == args
    plain = tile(pack_unit="", units_per_pack=1)
    assert _in_base_units("update_stock", plain, args, "add 2 boxes of floor tile") == args


def test_purchase_orders_are_converted_too():
    args = _in_base_units("create_purchase_order", tile(), {"reorder_qty": 5}, "order 5 boxes of floor tile")
    assert args["reorder_qty"] == 50


def test_converting_twice_is_a_no_op():
    once = _in_base_units("update_stock", tile(), {"qty_change": 2}, "add 2 boxes")
    assert _in_base_units("update_stock", tile(), once, "add 2 boxes") == once


# --- the fact layer ----------------------------------------------------------

NOW = datetime(2026, 10, 27, tzinfo=timezone.utc)


def raw_tile(**overrides):
    raw = {
        "id": "p1",
        "barcode": "1001",
        "name": "Floor Tile",
        "quantity": 53,
        "unit": "pcs",
        "baseUnit": "pcs",
        "packUnit": "box",
        "unitsPerPack": 10,
        "lowStockThreshold": 5,
    }
    raw.update(overrides)
    return raw


def test_facts_carry_the_pack_and_show_stock_in_packs():
    fact = derive_product_fact(raw_tile(), {}, {}, 90, NOW)
    assert fact.has_pack
    assert fact.in_packs(fact.quantity) == "5 box 3 pcs"
    brief = fact.brief()
    assert brief["stock_in_packs"] == "5 box 3 pcs"
    assert brief["pack"] == "1 box = 10 pcs"


def test_the_base_unit_wins_over_the_legacy_unit():
    fact = derive_product_fact(raw_tile(unit="box", baseUnit="pcs"), {}, {}, 90, NOW)
    assert fact.unit == "pcs"
    legacy = derive_product_fact(raw_tile(baseUnit=None, unit="kg", unitsPerPack=1), {}, {}, 90, NOW)
    assert legacy.unit == "kg"
    assert not legacy.has_pack
    assert "stock_in_packs" not in legacy.brief()


def test_a_unit_conversion_is_not_demand():
    # Re-counting 50 box as 500 pcs moves no goods; reading it as a sale or a
    # receipt would invent 450 units of demand.
    history = {"p1": [(NOW, "unit_conversion", 450), (NOW, "stock_out", 5)]}
    fact = derive_product_fact(raw_tile(), history, {}, 90, NOW)
    assert fact.units_out_window == 5
    assert fact.units_in_window == 0
