/// Which fields a bulk edit still needs a value for.
///
/// Extracted so the rule is testable on its own: the screen that uses it is a
/// four-step wizard behind a permission gate and several providers, which makes
/// a widget test a poor place to pin behaviour this specific.
///
/// The rule exists because every field in `_apply` is applied conditionally. An
/// unset category or an unparseable threshold was skipped in silence while the
/// other selected fields went through, and the run still reported full success
/// — so a user could come away certain they had changed a threshold across two
/// hundred products when nothing of the sort had happened.
library;

/// Field keys, matching the ones the wizard's step 2 stores.
class BulkEditField {
  BulkEditField._();

  static const String category = 'category';
  static const String company = 'company';
  static const String size = 'size';
  static const String threshold = 'threshold';
}

/// Human labels for the fields in [selectedFields] that have no usable value.
///
/// Empty means the edit is ready to apply. Order follows the wizard's own, so
/// the message reads in the order the fields appear on screen.
List<String> bulkEditMissingValues({
  required Set<String> selectedFields,
  String? category,
  String? company,
  String? size,
  String? thresholdText,
}) {
  return [
    if (selectedFields.contains(BulkEditField.category) && category == null)
      'Category',
    if (selectedFields.contains(BulkEditField.company) && company == null)
      'Company / Brand',
    if (selectedFields.contains(BulkEditField.size) && size == null)
      'Sub-Category',
    if (selectedFields.contains(BulkEditField.threshold) &&
        !isValidThreshold(thresholdText))
      'Low Stock Threshold',
  ];
}

/// True when [text] is a threshold the edit can actually write.
///
/// Zero is valid — it means "never warn" — so this is a lower bound of zero
/// rather than one, and anything unparseable or negative is not a value.
bool isValidThreshold(String? text) {
  final parsed = int.tryParse((text ?? '').trim());
  return parsed != null && parsed >= 0;
}

/// The sentence shown when [missing] is non-empty.
String bulkEditMissingValuesMessage(List<String> missing) {
  if (missing.isEmpty) return '';
  if (missing.length == 1) return 'Set a value for ${missing.first}';
  return 'Set values for ${missing.join(', ')}';
}
