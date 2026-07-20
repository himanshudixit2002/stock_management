from typing import List, Optional
from enum import Enum
from pydantic import BaseModel, Field


# --- Enums ---
class ScreenName(str, Enum):
    HOME = "home"
    INVENTORY = "inventory"
    ADD_PRODUCT = "add_product"
    EDIT_PRODUCT = "edit_product"
    SCANNER = "scanner"
    REPORTS = "reports"
    SETTINGS = "settings"
    PURCHASE_ORDERS = "purchase_orders"
    SALES_ORDERS = "sales_orders"
    VENDORS = "vendors"
    CUSTOMERS = "customers"


class ReportType(str, Enum):
    LOW_STOCK = "low_stock"
    SALES_SUMMARY = "sales_summary"
    INVENTORY_VALUATION = "inventory_valuation"


# --- Nested Schemas ---
class PurchaseOrderItem(BaseModel):
    product_name: str = Field(description="Name of the product to order.")
    barcode: str = Field(description="Barcode of the product.")
    quantity: int = Field(description="Quantity to order.", gt=0)


class SalesOrderItem(BaseModel):
    product_name: str = Field(description="Name of the product being sold.")
    barcode: str = Field(description="Barcode of the product.")
    quantity: int = Field(description="Quantity being sold.", gt=0)
    price: float = Field(description="Unit price for the item.", gt=0)


# --- Action Tool Schemas ---
class UpdateStock(BaseModel):
    """Update the stock quantity of a product."""
    product_name: str = Field(description="The name of the product to update.")
    barcode: str = Field(description="The exact alphanumeric barcode of the product.")
    qty_change: int = Field(description="Quantity to add (positive) or deduct (negative).")
    reason: Optional[str] = Field(default=None, description="Optional reason for the stock change.")


class CreatePurchaseOrder(BaseModel):
    """Create a new purchase order for restocking inventory."""
    vendor_name: str = Field(description="Name of the vendor/supplier.")
    items: List[PurchaseOrderItem] = Field(description="List of items to order.")
    notes: Optional[str] = Field(default=None, description="Optional notes for the order.")


class CreateSalesOrder(BaseModel):
    """Create a new sales order for outgoing inventory."""
    customer_name: str = Field(description="Name of the customer.")
    items: List[SalesOrderItem] = Field(description="List of items being sold.")
    notes: Optional[str] = Field(default=None, description="Optional notes for the order.")


class NavigateToScreen(BaseModel):
    """Navigate the user to a specific screen in the app."""
    target_screen: ScreenName = Field(description="The screen to navigate to.")
    params: Optional[dict] = Field(default=None, description="Optional parameters for the target screen.")


class GenerateReport(BaseModel):
    """Generate an inventory or sales report."""
    report_type: ReportType = Field(description="Type of report to generate.")
    format: str = Field(default="markdown", description="Output format for the report.")


class SearchProducts(BaseModel):
    """Search for products in inventory."""
    query: str = Field(description="Search query string.")
    category: Optional[str] = Field(default=None, description="Optional category filter.")


# All action tools for binding
ALL_ACTION_TOOLS = [
    UpdateStock,
    CreatePurchaseOrder,
    CreateSalesOrder,
    NavigateToScreen,
    GenerateReport,
    SearchProducts,
]
