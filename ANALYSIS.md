# Stock Management App – Codebase Analysis

## 1. Project Overview

| Aspect | Details |
|--------|---------|
| **Framework** | Flutter (web, Android) |
| **State** | Provider (6 providers) |
| **Backend** | Firebase Auth + Firestore |
| **Version** | 1.0.5+6 |

---

## 2. Architecture

### Directory Structure

```
lib/
├── config/       → theme.dart, routes.dart (AppRoutes – not used in app.dart)
├── models/       → product_model, category_model, vendor_model, user_model, stock_transaction_model
├── providers/   → auth, product, category, stock, vendor, settings
├── screens/     → auth, home, products, categories, stock, excel, vendors, users, reports, settings, dashboard
├── services/    → auth_service, database_service, excel_service, file_helper
├── utils/       → error_helpers, parse_helpers, dialogs, responsive
└── widgets/     → product_card, loading, empty_state, charts, etc.
```

### Firestore Schema (Multi-Tenant)

```
companies/{companyId}
├── products     → name, categoryId, quantity, locationQuantities, costPrice, sellingPrice, ...
├── categories   → name, description
├── transactions → productId, type (stock_in|out|damage|transfer), quantity, location, ...
├── vendors      → name, contactName, email, phone, ...
├── boms         → outputProductId, outputQuantity, components[], status
├── serials      → serialNumber, serialKey, productId, status, location, history[]
├── transferOrders   → fromLocation, toLocation, status, lines[] (ordered/dispatched/received)
├── requisitions     → title, urgency, status, lines[], vendorId, decidedBy, purchaseOrderId
├── recurringInvoices → customerId, items[], cadence, nextRunAt, generatedCount
├── priceLists   → name, defaultDiscountPercent, entries[], customerIds[]
├── landedCosts  → purchaseOrderId, charges[], lines[], status
├── quotations   → customerId, status, lines[], validUntil, convertedSalesOrderId
├── shipments    → salesOrderId, status, lines[] (ordered/picked/packed), carrier, tracking
├── expenses     → category, amount, taxAmount, status, expenseDate, vendorId
├── registerSessions → registerName, openingFloat, movements[], expectedCash, countedCash
│                      (also holds one `lock_<register>` doc per till — the
│                       one-open-shift invariant, since a transaction cannot query)
├── commissionPlans  → basis (revenue|margin), defaultPercent, categoryRates[], userIds[]
├── budgets      → period, periodStart, lines[] (revenue|purchases|expense heads)
├── serviceJobs  → customerId, serialId, status, parts[] (issued flag), charges[]
├── jobWorkOrders → vendorId, outputProductId, components[] (issued/consumed), status
│
│  Every one of these is listed in `SuperAdminService.companyCollections`, which
│  the platform console counts and browses and a workspace purge iterates. A
│  contract test pins the list against the collections the code writes.
└── (company doc) → settings: { pricingEnabled, vendorsEnabled, companies[], sizes[], locations[] }

users/{uid}      → role, companyId, approved, permissions
```

---

## 3. Data Loading Patterns

| Provider | Pattern | Notes |
|----------|---------|-------|
| ProductProvider | One-shot paginated (`getProductsPage`) | No real-time; refresh via `refreshProducts()` |
| CategoryProvider | Firestore stream | Live updates |
| StockProvider | Firestore stream (limit 500) | Live updates |
| VendorProvider | Firestore stream | Live updates |
| SettingsProvider | One-shot read | Company settings |

---

## 4. Fixed Issues (This Session)

1. **Excel Export – `companyId` bug**
   - `_databaseService.getAllTransactionsOnce()` was called without `setCompanyId()`, causing `StateError`.
   - Fix: Call `_databaseService.setCompanyId(currentUser.companyId)` before transactions/full export.

2. **Product list not refreshing after add/edit/delete**
   - List showed stale data until manual refresh.
   - Fix: Call `await refreshProducts()` after successful add, update, delete.

3. **Import quantity 0 when Locations = "pos1" (name only)**
   - Locations like `"pos1"` (no `pos1:123`) parsed as qty 0, overwriting Quantity column.
   - Fix: When location sum is 0 and Quantity column > 0, assign that quantity to the location(s).

4. **Import preview missing Locations column**
   - Added Locations column to match export format.

5. **Excel sheets: Sheet1 + Products duplicates**
   - Use default sheet and rename at end instead of creating extra sheets.

---

## 5. Remaining Considerations

### Potential Improvements

| Area | Notes |
|------|-------|
| **AppRoutes** | `routes.dart` defines constants but `app.dart` uses string literals in `onGenerateRoute` |
| **DatabaseService instances** | Each provider and ExcelExportScreen create their own; `companyId` must be set per use |
| **Bulk import partial failure** | `bulkAddProducts` commits in batches of 450; a later batch failure leaves partial data |
| **Transaction limit** | `getAllTransactionsOnce` has no limit; `getAllTransactions` stream uses 500. Full report export fetches all |
| **Settings merge** | `togglePricing` / `toggleVendors` use `set(merge: true)` with partial `settings` object – generally safe |
| **Offline** | No offline persistence; all data requires Firestore connectivity |
| **Tests** | Only `test/widget_test.dart` (basic); no unit/integration tests for services or providers |

### Excel Service Notes

- **Column mapping**: Excel and CSV parsers have similar but separate logic (`_inferColumnsFromData` vs `_inferColumnsFromCsvData`).
- **Locations format**: Supports `Location:Qty` (e.g. `pos1:123`) or location name only (falls back to Quantity column).
- **Headerless files**: Column inference by data type; `preferredVendor` not inferred for headerless CSVs.

### Security

- Firestore rules enforce `belongsToCompany(companyId)`.
- User permissions (`canManageProducts`, `canImport`, etc.) checked in UI.

---

## 6. Key Flows

```
Auth:  Landing → Login/Register → (Pending Approval) → Home
       Providers initialized with companyId in AuthWrapper

Products: List (paginated, Load more) → Add/Edit/Detail → Stock In/Out/Transfer/Damage
          Refresh after add/edit/delete

Excel:   Import: Pick file → Parse → Preview → bulkAddProducts
         Export: Products | Transactions | Categories | Full report (Excel/CSV)
```


---

## 7. Summary

The app has a clear structure with multi-tenant Firestore and provider-based state. Critical issues (Excel export `companyId`, product refresh, import quantity for location-only format) have been addressed. Remaining items are improvements and long-term maintainability rather than blockers.

---

## 8. Runbook: the AI assistant stops answering

Symptom: every question in Ask AI comes back "the assistant service is
unavailable", and the AI dashboard tiles report an error.

The assistant is the one feature that leaves Firebase — it calls a Cloud Run
service (`rag-backend`, `asia-south1`) which answers from Firestore facts and
Vertex AI. Everything else in the app keeps working while it is down, which is
why an outage here is easy to misread as a client bug.

Check in this order. The first two take seconds and settle it most of the time:

```bash
# 1. Is the backend serving at all?
curl -s -o /dev/null -w '%{http_code}\n' \
  https://rag-backend-647731796550.asia-south1.run.app/health

# 2. If not 200, read the reason. This is the step that matters -- Cloud Run
#    explains itself here and nowhere else.
gcloud logging read 'resource.type="cloud_run_revision" AND
  resource.labels.service_name="rag-backend"' --limit 20 --freshness=1h \
  --format='value(timestamp,severity,httpRequest.status,textPayload)'
```

**A 500 or 503 that returns in well under a second never reached the container.**
Cloud Run rejected it at the front door, so the service description will look
perfectly healthy — `ContainerHealthy: True`, 100% traffic, `allUsers` invoker —
and reading that description first is a dead end. This happened on 2026-09-09:
the request log said `The request failed because billing is disabled for this
project`, because the project's billing account had been closed.

Beware the field that reads correctly while being useless:
`gcloud billing projects describe` reports `billingEnabled: true` when an account
is merely *attached*. A **closed** account still reports true and still refuses
every request. The state that matters is `open` on the account itself:

```bash
gcloud billing accounts describe ACCOUNT_ID --format='value(open)'
```

`bash scripts/restore_ai_backend.sh` performs this whole check, applies the cost
settings below, and polls until healthy. It deliberately stops short of linking
billing — which account pays is a decision for a person, not a script.

**Cost shape.** The service ran at `min-instances: 1`, holding 2 vCPU and 1 GiB
allocated 24 hours a day whether or not anybody asked a question; for a
bursty internal assistant that is the entire idle bill. It is now
`min-instances: 0` with `max-instances: 4`. Scale-to-zero costs a cold start —
the container measures about six seconds to healthy, softened by
`startup-cpu-boost` and survivable because the client retries once and falls back
from streaming to a plain request. The instance ceiling bounds the worst case,
since every request can call a paid model.
