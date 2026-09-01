/// Matching rules for the Settings search field.
///
/// Extracted so the semantics are testable on their own: the screen that uses
/// it needs half a dozen providers to build, which makes a widget test a poor
/// place to pin behaviour like case-insensitivity or whether the subtitle
/// counts.
library;

/// True when a settings entry should survive [query].
///
/// Both the title and the subtitle are searched, because the subtitle is
/// usually where the words a user actually thinks in live — "tax" and
/// "numbering" appear only in Billing Settings' subtitle, never its title.
bool settingsEntryMatches(String title, String? subtitle, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (title.toLowerCase().contains(q)) return true;
  return subtitle != null && subtitle.toLowerCase().contains(q);
}

/// True when a whole section should be kept because its own name matches.
///
/// A section title match keeps everything inside it: someone typing "account"
/// wants the Account section entire, not just the rows that repeat the word.
bool settingsSectionMatches(String sectionTitle, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return sectionTitle.toLowerCase().contains(q);
}
