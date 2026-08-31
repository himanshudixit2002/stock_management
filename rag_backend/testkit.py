"""Shared setup for backend tests.

Two things changed that every suite has to account for:

  * A company id is now mandatory. There is no `default` sandbox to fall back
    to, because falling back is exactly what showed one tenant another's data.
  * There is no seeded demo inventory. Tests state the stock they need.

`OFFLINE_MODE=1` is the only switch that reaches the local JSON store, so tests
opt into it explicitly rather than inheriting it from a magic company name.
"""

import os

os.environ["OFFLINE_MODE"] = "1"

TEST_COMPANY = "test_company"

DEFAULT_PRODUCTS = [
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


def headers(company_id: str = TEST_COMPANY) -> dict:
    """Headers every data endpoint now requires."""
    return {"x-company-id": company_id}


def seed(products=None, company_id: str = TEST_COMPANY):
    """Replace the offline catalog for `company_id` and return the fresh facts."""
    from facts import fact_store
    from inventory_db import db_instance

    db_instance.replace_user_inventory(
        [dict(p) for p in (products or DEFAULT_PRODUCTS)], company_id=company_id
    )
    fact_store.bump(company_id)
    return fact_store.get(company_id, force=True)


def product(company_id: str = TEST_COMPANY, barcode: str = "89010001"):
    from facts import fact_store

    return fact_store.get(company_id).by_barcode(barcode)
