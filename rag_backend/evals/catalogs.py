"""Named seed catalogs, with their arithmetic stated up front.

Every figure in ``GROUND_TRUTH`` is computed here by hand rather than read back
out of the fact layer. An eval that derives its expected value from the code
under test proves only that the code agrees with itself; these numbers are the
independent side of the comparison, and they are what the Reports screen has to
agree with too.
"""

from __future__ import annotations

from typing import Any, Dict, List

# The same four products the backend tests seed, so a failure here and a failure
# in ``test_facts.py`` are talking about the same inventory.
DEFAULT: List[Dict[str, Any]] = [
    {
        "id": "p_apples",
        "barcode": "89010001",
        "name": "Fresh Apples (kg)",
        "stock": 15,
        "min_threshold": 50,
        "category": "Produce",
        "cost_price": 1.20,
        "selling_price": 2.50,
    },
    {
        "id": "p_laptops",
        "barcode": "89010002",
        "name": "Pro Laptops 15-inch",
        "stock": 100,
        "min_threshold": 20,
        "category": "Electronics",
        "cost_price": 650.00,
        "selling_price": 999.00,
    },
    {
        "id": "p_water",
        "barcode": "89010003",
        "name": "Sparkling Water Pack of 12",
        "stock": 200,
        "min_threshold": 100,
        "category": "Beverages",
        "cost_price": 4.00,
        "selling_price": 8.99,
    },
    {
        "id": "p_milk",
        "barcode": "89010004",
        "name": "Organic Whole Milk 1L",
        "stock": 8,
        "min_threshold": 30,
        "category": "Dairy",
        "cost_price": 1.50,
        "selling_price": 2.99,
    },
]

# One product, sitting at zero. Separates "nothing in stock" from "nothing in
# the catalog", which are different answers and used to be the same one.
SINGLE_OUT_OF_STOCK: List[Dict[str, Any]] = [
    {
        "id": "p_gone",
        "barcode": "89020001",
        "name": "Discontinued Gadget",
        "stock": 0,
        "min_threshold": 5,
        "category": "Electronics",
        "cost_price": 10.00,
        "selling_price": 25.00,
    },
]

# A workspace that has been created but never filled. The honest answer is that
# there is no catalog yet — not a confident report over zero rows.
EMPTY: List[Dict[str, Any]] = []

CATALOGS: Dict[str, List[Dict[str, Any]]] = {
    "default": DEFAULT,
    "single_out_of_stock": SINGLE_OUT_OF_STOCK,
    "empty": EMPTY,
}

#   apples 15 × 2.50 =     37.50      laptops 100 × 999.00 = 99900.00
#   water 200 × 8.99 =   1798.00      milk      8 ×   2.99 =    23.92
#                                                    total = 101759.42
#   cost: 18.00 + 65000.00 + 800.00 + 12.00          total =  65830.00
GROUND_TRUTH: Dict[str, Dict[str, Any]] = {
    "default": {
        "total_products": 4,
        "low_stock_count": 2,          # apples 15<50, milk 8<30
        "out_of_stock_count": 0,
        "retail_value": 101759.42,
        "cost_value": 65830.00,
        "low_stock_names": ["Fresh Apples (kg)", "Organic Whole Milk 1L"],
        "barcodes": ["89010001", "89010002", "89010003", "89010004"],
    },
    "single_out_of_stock": {
        "total_products": 1,
        "low_stock_count": 1,          # zero is below the threshold of 5
        "out_of_stock_count": 1,
        "retail_value": 0.0,
        "cost_value": 0.0,
        "low_stock_names": ["Discontinued Gadget"],
        "barcodes": ["89020001"],
    },
    "empty": {
        "total_products": 0,
        "low_stock_count": 0,
        "out_of_stock_count": 0,
        "retail_value": 0.0,
        "cost_value": 0.0,
        "low_stock_names": [],
        "barcodes": [],
    },
}


def catalog(name: str) -> List[Dict[str, Any]]:
    if name not in CATALOGS:
        raise KeyError(f"unknown catalog {name!r}; have {sorted(CATALOGS)}")
    return [dict(p) for p in CATALOGS[name]]


def truth(name: str) -> Dict[str, Any]:
    return GROUND_TRUTH[name]
