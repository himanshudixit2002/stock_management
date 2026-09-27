/// What Bulk Stock In should show instead of the entry form, if anything.
///
/// Extracted for the same reason as `bulk_edit_validation.dart`: the screen is
/// behind a permission gate and three providers, which makes a widget test a
/// poor place to pin a rule this specific.
///
/// The rule exists because the screen used to gate on the product list alone.
/// Every row also needs a location, and that dropdown is fed entirely from
/// workspace settings, which start empty — so on a fresh workspace the form
/// rendered, accepted a product and a quantity, and then refused to submit with
/// "Please select a location for each row". True, and useless: there was
/// nothing to select and no hint that Settings was where to go.
library;

/// The blocking state of the screen, in the order it is decided.
enum BulkStockInGate {
  /// The catalog has not arrived yet. Distinct from [noProducts]: "we do not
  /// know" and "there are none" are different statements.
  loading,

  /// The workspace has no products, so there is nothing to stock in.
  noProducts,

  /// Products exist but no locations are configured, so no row can be
  /// completed.
  noLocations,

  /// Show the form.
  ready,
}

/// Decides which state applies.
///
/// [isFullCatalogLoaded] is the authoritative signal; the two loading flags
/// only matter before it flips, and only while nothing has arrived yet.
BulkStockInGate bulkStockInGate({
  required bool isFullCatalogLoaded,
  required bool isLoadingAnalytics,
  required bool isLoadingProducts,
  required int productCount,
  required int locationCount,
}) {
  if (!isFullCatalogLoaded &&
      productCount == 0 &&
      (isLoadingAnalytics || isLoadingProducts)) {
    return BulkStockInGate.loading;
  }
  if (productCount == 0) return BulkStockInGate.noProducts;
  // Deliberately after the product check: with neither products nor locations,
  // "add a product" is the more useful of the two things to be told first.
  if (locationCount == 0) return BulkStockInGate.noLocations;
  return BulkStockInGate.ready;
}
