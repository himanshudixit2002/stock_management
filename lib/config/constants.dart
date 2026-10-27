const int kFirestoreBatchLimit = 450;
const int kDefaultLowStockThreshold = 10;
const int kSearchDebounceMs = 300;
const String kDefaultUnit = 'pcs';
const int kPaginationLimit = 200;
const int kMaxProductsPerPage = 2000;

/// The units a workspace starts with, until it edits its own list in
/// Settings › Units. These are what the product form offered before units
/// became editable, so an untouched workspace sees no change.
const List<String> kDefaultUnits = [
  'pcs',
  'kg',
  'ltr',
  'box',
  'pack',
  'dozen',
  'meter',
  'set',
  'sqft',
  'bundle',
];
