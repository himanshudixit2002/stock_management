# Feature Plan — ten new modules

Ten features that the app does not have today, each specified as a complete
vertical slice. They were chosen to sit on top of what already exists rather
than beside it: every one reuses the products, transactions, orders or invoices
that are already modelled, so none of them introduces a second source of truth.

## What "synced" means here

A feature in this codebase is not finished when its screen renders. The
information architecture is data-driven, and a feature that skips any of these
is invisible, unreachable, or silently ungoverned:

| Surface | File | What breaks if skipped |
|---|---|---|
| Route constant | `lib/config/routes.dart` | Nothing can name the destination |
| Route case | `lib/config/router.dart` | Deep links and pushes fall through |
| Permission keys + defs | `lib/config/permissions.dart` | Role editor cannot grant it; staff get it unconditionally |
| Catalog entry | `lib/config/feature_map.dart` | Missing from Home, tab headers, Plan & Features, tier editor, search |
| Provider registration | `lib/app.dart` | `context.read` throws; state survives sign-out into the next tenant |
| Collection + CRUD | `lib/services/database_service.dart` | No tenant scoping, no plan caps, no audit trail |
| Security rules | `firestore.rules` | The permission key is decoration — the server allows anything |
| Composite indexes | `firestore.indexes.json` | Ordered/filtered queries fail in production only |
| Tests | `test/` | Regressions land silently |

Every feature below states its full row in that table.

---

## 1. Bill of Materials & Assembly

**Collection:** `companies/{id}/boms`

Define a finished product as a set of component products with per-unit
quantities. Building consumes components and produces finished goods in one
Firestore transaction, so a partial build cannot exist. Unbuilding reverses it.

- **Model:** `BomModel` (`outputProductId`, `outputQuantity`, `components[]`,
  `status`, `wastagePercent`, `notes`)
- **Screens:** BOM list, BOM editor, Build/Unbuild sheet
- **Permissions:** `canViewBoms`, `canManageBoms`, `canBuildAssemblies`
- **Movements:** component `stockOut` rows + output `stockIn` rows, reason
  `Assembly build #<id>`, all inside `runTransaction`
- **Why it matters:** every assembler, kitter and bundler currently has to fake
  this with two manual stock movements and no link between them.

## 2. Serial Number Tracking

**Collection:** `companies/{id}/serials`

Unit-level identity below the batch. A serial belongs to one product, carries a
status (`inStock`, `sold`, `returned`, `scrapped`), a location, an optional
batch, and the document that last moved it.

- **Model:** `SerialModel`
- **Screens:** serial register (search + filter), serial detail with history,
  bulk register sheet
- **Permissions:** `canViewSerials`, `canManageSerials`
- **Lookup:** on `serialKey` — the number upper-cased with whitespace collapsed
  — so "sn 001", "SN-001 " and "SN 001" cannot become three different units
- **Why it matters:** warranty, RMA and theft investigations are impossible at
  batch granularity.

## 3. Transfer Orders (in-transit stock)

**Collection:** `companies/{id}/transferOrders`

Today `transferStock` moves stock between locations instantly. Real transfers
take days, and stock in a truck belongs to neither end. A transfer order moves
`draft → dispatched → received`, holding the quantity in an explicit in-transit
bucket in between, and supports partial receipt and cancellation.

- **Model:** `TransferOrderModel` with `TransferOrderLine[]`
- **Screens:** list, create, detail (dispatch / receive / cancel)
- **Permissions:** `canViewTransferOrders`, `canCreateTransferOrders`,
  `canDispatchTransferOrders`, `canReceiveTransferOrders`
- **Movements:** dispatch writes a `transfer` row out of the source; receipt
  writes a `transfer` row into the destination
- **Why it matters:** multi-location workspaces currently either lose visibility
  of moving stock or double-count it.

## 4. Purchase Requisitions & Approvals

**Collection:** `companies/{id}/requisitions`

An internal request to buy, separate from the purchase order it may become.
`draft → submitted → approved/rejected → converted`. Approval is a distinct
permission from creation, which is the entire point.

- **Model:** `RequisitionModel` with `RequisitionLine[]`
- **Screens:** list, create, detail (approve / reject / convert to PO)
- **Permissions:** `canViewRequisitions`, `canCreateRequisitions`,
  `canApproveRequisitions`
- **Why it matters:** the PO screen is the only way to ask for stock today, and
  it is gated on the permission that also commits company money.

## 5. Tax (GST) Summary Report

**Derived — no new collection.** Reads invoices.

Period-scoped summary of output tax (sales invoices) and input tax (purchase
invoices), broken down by tax rate, with taxable value, tax amount and invoice
count per slab, plus a net payable line. Exports through the existing report
export path.

- **Screen:** tax summary report
- **Service:** `TaxSummaryService` — pure, unit-testable, no Firestore
- **Permissions:** `canViewTaxReports`
- **Why it matters:** the numbers for a GST return already exist in the
  invoices; nothing surfaces them, so every filing is a manual re-add.

## 6. Recurring Invoices

**Collection:** `companies/{id}/recurringInvoices`

A saved invoice template plus a cadence (`weekly`, `monthly`, `quarterly`,
`yearly`), a start date, an optional end date, and a computed `nextRunAt`.
Generating is explicit and idempotent: a run stamps `lastRunAt` and advances
`nextRunAt`, so pressing the button twice cannot bill a customer twice.

- **Model:** `RecurringInvoiceModel`
- **Screens:** schedule list (with a "due now" banner), schedule editor
- **Permissions:** `canViewRecurringInvoices`, `canManageRecurringInvoices`
- **Why it matters:** subscription and retainer billing is re-keyed by hand
  every cycle.

## 7. Customer Price Lists & Discount Tiers

**Collection:** `companies/{id}/priceLists`

A named list holding per-product price overrides and a default discount
percent, assignable to customers. Resolution order is explicit and shared by
POS and invoicing: product override → list discount → product selling price.

- **Model:** `PriceListModel`, `PriceListEntry`
- **Service:** `PriceListResolver` — pure, unit-testable
- **Screens:** price list index, price list editor
- **Permissions:** `canViewPriceLists`, `canManagePriceLists`
- **Why it matters:** wholesale and retail pricing are the same field today, so
  every trade sale is discounted by hand.

## 8. Barcode & Shelf Label Printing

**Derived — no new collection.** Reads products.

Composes a printable PDF sheet of labels — name, SKU/barcode, price, optional
MRP — in a configurable grid (Avery-style presets plus a custom grid), with
per-product copy counts. Uses `pdf` + `printing`, already in the dependency set;
`pw.BarcodeWidget` comes from `pdf`, so nothing new is added.

- **Screen:** label designer + preview
- **Service:** `LabelPdfService`
- **Permissions:** `canPrintLabels`
- **Why it matters:** the app can scan barcodes it has no way to produce.

## 9. Dead Stock & Slow-Mover Analysis

**Derived — no new collection.** Reads products + transactions.

Ranks products by days since last outbound movement against the capital they
tie up, bucketing into fresh / slowing / stale / dead, with a configurable
threshold and a total "value at rest" figure.

- **Screen:** dead stock report
- **Service:** `DeadStockService` — pure, unit-testable
- **Permissions:** reuses `canViewReports`
- **Why it matters:** the reports answer what sells; nothing answers what has
  stopped selling, which is where the working capital actually goes.

## 10. Landed Cost Allocation

**Collection:** `companies/{id}/landedCosts`

Freight, duty and handling charges attached to a received purchase order, then
allocated across its lines by value, quantity or weight. Applying updates each
product's `costPrice` and writes a `priceHistory` row, so margins and valuation
reflect what the stock actually cost to land.

- **Model:** `LandedCostModel`, `LandedCostCharge`
- **Service:** `LandedCostAllocator` — pure, unit-testable
- **Screens:** landed cost list, allocation editor
- **Permissions:** `canViewLandedCosts`, `canManageLandedCosts`
- **Why it matters:** cost price is the purchase price today, so every margin
  report overstates profit by the whole cost of getting the goods in.

---

## Plan tiering

All ten are catalogued in `FeatureMap`, so the platform console's tier editor
can lock any of them per plan without a code change. The compiled seed tiers
lock the heavier modules on the entry tiers:

- **Starter** additionally locks: BOM, serials, transfer orders, requisitions,
  recurring invoices, price lists, landed costs
- **Growth** additionally locks: BOM, serials, landed costs
- **Pro / MAX**: everything

## Rollout order

1. Pure services first (5, 8, 9) — no schema, no rules, unit-testable alone.
2. Then the collection-backed modules (1, 2, 3, 4, 6, 7, 10).
3. Wiring last, in one pass across the nine surfaces above.

---

## What landed

All ten, wired across every surface in the table above. Notes on the decisions
that were made while building rather than while planning:

**In-transit is a location, not a state.** Dispatching a transfer moves stock
into a virtual `In transit` bucket in `locationQuantities` rather than removing
it. Total on-hand is therefore constant across the whole journey, which is what
keeps valuation and the stock ledger reconciling while a shipment is on the
road — and it is why the transfer rows still net to zero.

**Atomicity where a half-write would destroy stock.** `runAssembly`,
`_moveTransferStock`, `decideRequisition`, `convertRequisitionToPurchaseOrder`,
`generateRecurringInvoice` and `applyLandedCost` each do all their reads before
any write inside one `runTransaction`. A build that consumed components and
failed before creating the finished goods would be worse than no feature at all.

**Idempotent generation.** `generateRecurringInvoice` re-reads the schedule
inside the transaction and bails if it is no longer due, and advances
`nextRunAt` in the same write that creates the invoice. Two people pressing
"Generate due" at the same moment produce one invoice.

**Pricing has one implementation.** `PriceListResolver` is shared by the
invoice editor and Fast POS. Choosing the customer after items are scanned
reprices the cart, because that is the order things happen at a counter.

**No composite indexes were needed.** Every query these modules make is a
single-field `orderBy` or a single-field equality, all covered by Firestore's
automatic single-field indexes, so `firestore.indexes.json` is unchanged.

**Verification.**

- `flutter analyze lib` — clean; the only remaining infos pre-date this work.
- `flutter test` — the full suite, plus new tests for the tax summary, dead
  stock analysis, price resolution, landed cost allocation, and the BOM,
  serial, transfer order and recurring schedule models.
- `test/config/feature_catalog_contract_test.dart` pins the sync itself: every
  catalogued feature names a real permission, every plan lock names a real
  feature, and no tier locks something a cheaper tier leaves open.
- The Firestore rules suite runs against the emulator: 119 passing, including
  46 new ones covering cross-tenant reads, view-without-write, the
  build-may-update-but-not-create carve-out, suspension, and the platform
  admin's read-but-never-write boundary.
