# Implementation Plan

## Goal
Enhance Excel import functionality to robustly handle vendor information, phone numbers, and related edge cases. This includes:
- Proper parsing of vendor name and phone number from Excel files.
- Validation and normalization of phone numbers.
- Graceful handling of missing or malformed vendor data.
- Updating diff logic to correctly match products by vendor when IDs are absent.
- Adding comprehensive error reporting for import failures.

## User Review Required
> [!IMPORTANT]
> This change introduces new validation rules and may affect existing import workflows. Ensure you review:
> - Phone number format expectations.
> - Whether existing Excel files need to be updated to match new column names.
> - Impact on existing vendor‑related UI screens.

## Open Questions
> [!WARNING]
> 1. Preferred phone number format (E.164, local, etc.)?
> 2. Should we auto‑create a vendor if it does not exist? (Yes/No)
> 3. Any specific delimiter for multiple phone numbers in a single cell?

## Proposed Changes
---
### Excel Service (lib/services/excel_service.dart)
- **[MODIFY] excel_service.dart**: Extend `parseExcelBytes` and `parseForUpdate` to include `vendor` and `phone` columns.
- Add helper `_normalizePhone(String)` to clean and format phone numbers.
- Introduce validation that logs skipped rows with invalid phone numbers.
- Update `ParseResult` to include a list of `skippedRows` with reasons.
- Adjust `diffProducts` to match vendors using normalized phone numbers when IDs are missing.

---
### Vendor Provider (if applicable)
- **[MODIFY] lib/providers/vendor_provider.dart**: Add method `getOrCreateVendorByName(String name, String phone)` to optionally create missing vendors.

---
### UI Feedback
- **[MODIFY] lib/screens/excel/excel_import_screen.dart**: Show detailed import summary including rows skipped due to vendor/phone issues.

---
### Tests
- Add unit tests for new phone normalization and vendor matching logic.

## Verification Plan
### Automated Tests
- Run existing test suite (`flutter test`).
- Add new tests for Excel import edge cases.

### Manual Verification
- Import an Excel file with various vendor name/phone scenarios:
  - Missing vendor.
  - Invalid phone format.
  - Multiple vendors.
- Verify that errors are reported and valid rows are imported.
- Confirm that vendor lookup works during update diff.

