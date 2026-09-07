/// Matching rules for the Settings search field.
///
/// Extracted so the semantics are testable on their own: the screen that uses
/// it needs half a dozen providers to build, which makes a widget test a poor
/// place to pin behaviour like case-insensitivity or whether the subtitle
/// counts.
library;

import '../../config/settings_catalog.dart';

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

// -----------------------------------------------------------------------------
// Leaf-level search
// -----------------------------------------------------------------------------

/// One setting matching a query, with the trail that says where it lives.
///
/// The old search could only match the rows Settings happened to have built,
/// which meant every setting one page deeper was invisible to it: "currency",
/// "gst", "expiry" and "invoice prefix" all returned "Nothing matches" while
/// sitting in Billing Settings and Notification Settings. Searching the catalog
/// instead of the widget tree is what makes those findable.
class SettingsSearchHit {
  const SettingsSearchHit({
    required this.leaf,
    required this.breadcrumb,
    required this.score,
  });

  final SettingsLeaf leaf;

  /// Where the setting lives, e.g. `Billing & invoicing · Tax`. Without it a
  /// result list of bare titles gives no clue which page a tap will open.
  final String breadcrumb;

  final int score;
}

/// Where [leaf] lives, for the result row's second line.
String breadcrumbFor(SettingsLeaf leaf) {
  final category = SettingsCatalog.categoryTitle(leaf.category);
  final group = leaf.group;
  return group == null ? category : '$category · $group';
}

/// How strongly [leaf] answers [query]. Zero means no match.
///
/// Ranked so the most literal reading wins: someone typing "theme" wants the
/// Theme row, not every row whose description mentions themes. Keywords sit
/// below titles but above subtitles because they are deliberate synonyms
/// ("gst" for the tax rate) rather than incidental prose.
int scoreSettingsLeaf(SettingsLeaf leaf, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;

  final title = leaf.title.toLowerCase();
  if (title == q) return 100;
  if (title.startsWith(q)) return 80;
  if (title.contains(q)) return 60;

  var best = 0;
  for (final keyword in leaf.keywords) {
    final k = keyword.toLowerCase();
    if (k == q) {
      best = best < 50 ? 50 : best;
    } else if (k.contains(q)) {
      best = best < 35 ? 35 : best;
    }
  }
  if (best > 0) return best;

  if ((leaf.group ?? '').toLowerCase().contains(q)) return 25;
  // Reuses the tile matcher so the subtitle rule stays one definition.
  if (settingsEntryMatches('', leaf.subtitle, q)) return 20;
  if (SettingsCatalog.categoryTitle(leaf.category).toLowerCase().contains(q)) {
    return 10;
  }
  return 0;
}

/// Settings matching [query] that [ctx] is allowed to see, best first.
///
/// An empty query returns nothing rather than everything: on the hub a blank
/// field means "show me the categories", and returning all fifty leaves would
/// bury them.
List<SettingsSearchHit> searchSettings(
  String query, {
  required SettingsVisibilityContext ctx,
  List<SettingsLeaf> leaves = SettingsCatalog.leaves,
  int limit = 25,
}) {
  if (query.trim().isEmpty) return const [];

  final hits = <SettingsSearchHit>[];
  for (final leaf in leaves) {
    if (!isSettingVisible(leaf, ctx)) continue;
    final score = scoreSettingsLeaf(leaf, query);
    if (score == 0) continue;
    hits.add(
      SettingsSearchHit(
        leaf: leaf,
        breadcrumb: breadcrumbFor(leaf),
        score: score,
      ),
    );
  }

  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byOrder = a.leaf.sortOrder.compareTo(b.leaf.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.leaf.title.compareTo(b.leaf.title);
  });

  return hits.length > limit ? hits.sublist(0, limit) : hits;
}
