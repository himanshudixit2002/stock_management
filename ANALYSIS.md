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
