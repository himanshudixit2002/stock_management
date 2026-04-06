import 'dart:math' as math;

import '../models/product_model.dart';

/// Normalized free-text: lowercase, trim, collapse whitespace.
String normalizeProductSearchText(String q) {
  return q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Alphanumeric only for barcode / SKU style matching.
String compactProductToken(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Whether [p]'s stored barcode matches a camera/manual [scannedRaw] value.
/// Uses case-insensitive equality and compact (alphanumeric-only) equality
/// so formats like `890-123-456` and `890123456` match.
bool productMatchesBarcodeScan(ProductModel p, String scannedRaw) {
  final stored = p.barcode.trim();
  if (stored.isEmpty) return false;
  final scan = scannedRaw.trim();
  if (scan.isEmpty) return false;
  if (stored.toLowerCase() == scan.toLowerCase()) return true;
  final a = compactProductToken(stored);
  final b = compactProductToken(scan);
  if (a.isEmpty || b.isEmpty) return false;
  return a == b;
}

/// Barcode-aware match (see [productMatchesBarcodeScan]) or product name contains query.
List<ProductModel> productsMatchingBarcodeOrName(
  List<ProductModel> products,
  String query,
) {
  final trimmed = query.trim();
  final q = trimmed.toLowerCase();
  if (q.isEmpty) return [];
  return products
      .where(
        (p) =>
            (p.barcode.isNotEmpty && productMatchesBarcodeScan(p, trimmed)) ||
            p.name.toLowerCase().contains(q),
      )
      .toList();
}

class ProductSearchFilters {
  const ProductSearchFilters({
    this.stock,
    this.categorySubstr,
    this.companySubstr,
    this.locationSubstr,
    this.vendorSubstr,
  });

  /// `out` | `low` | `in`
  final String? stock;
  final String? categorySubstr;
  final String? companySubstr;
  final String? locationSubstr;
  final String? vendorSubstr;
}

class ParsedProductQuery {
  const ParsedProductQuery({
    required this.filters,
    required this.freeTextTokens,
  });

  final ProductSearchFilters filters;
  final List<String> freeTextTokens;
}

final RegExp _structuredTokenRe = RegExp(
  r'\b(stock|cat|category|company|loc|location|vendor):(\S+)',
  caseSensitive: false,
);

/// Pulls `key:value` pairs from [query]; remaining text becomes [freeTextTokens].
ParsedProductQuery parseProductSearchQuery(String query) {
  var rest = query.trim();
  String? stock;
  String? categorySubstr;
  String? companySubstr;
  String? locationSubstr;
  String? vendorSubstr;

  for (final m in _structuredTokenRe.allMatches(rest)) {
    final key = m.group(1)!.toLowerCase();
    final rawVal = m.group(2)!;
    final val = normalizeProductSearchText(rawVal);
    if (val.isEmpty) continue;

    switch (key) {
      case 'stock':
        final v = val.replaceAll('-', '');
        if (v == 'out' || v == 'oos') {
          stock = 'out';
        } else if (v == 'low' || v == 'lowstock') {
          stock = 'low';
        } else if (v == 'in' || v == 'instock') {
          stock = 'in';
        }
        break;
      case 'cat':
      case 'category':
        categorySubstr = val;
        break;
      case 'company':
        companySubstr = val;
        break;
      case 'loc':
      case 'location':
        locationSubstr = val;
        break;
      case 'vendor':
        vendorSubstr = val;
        break;
    }
  }

  rest = rest.replaceAll(_structuredTokenRe, ' ');
  final normalized = normalizeProductSearchText(rest);
  final freeTextTokens = normalized.isEmpty
      ? <String>[]
      : normalized.split(' ').where((t) => t.isNotEmpty).toList();

  return ParsedProductQuery(
    filters: ProductSearchFilters(
      stock: stock,
      categorySubstr: categorySubstr,
      companySubstr: companySubstr,
      locationSubstr: locationSubstr,
      vendorSubstr: vendorSubstr,
    ),
    freeTextTokens: freeTextTokens,
  );
}

bool productPassesSearchFilters(ProductModel p, ProductSearchFilters f) {
  if (f.stock != null) {
    switch (f.stock) {
      case 'out':
        if (!p.isOutOfStock) return false;
        break;
      case 'low':
        if (!p.isLowStock) return false;
        break;
      case 'in':
        if (!p.isInStock) return false;
        break;
    }
  }
  if (f.categorySubstr != null && f.categorySubstr!.isNotEmpty) {
    if (!p.categoryName.toLowerCase().contains(f.categorySubstr!)) {
      return false;
    }
  }
  if (f.companySubstr != null && f.companySubstr!.isNotEmpty) {
    if (!p.company.toLowerCase().contains(f.companySubstr!)) {
      return false;
    }
  }
  if (f.locationSubstr != null && f.locationSubstr!.isNotEmpty) {
    final loc = f.locationSubstr!;
    final any = p.locationQuantities.keys.any(
      (k) => k.toLowerCase().contains(loc),
    );
    if (!any) return false;
  }
  if (f.vendorSubstr != null && f.vendorSubstr!.isNotEmpty) {
    final v = f.vendorSubstr!;
    final pref = p.preferredVendorName.toLowerCase().contains(v);
    final last = p.lastVendorName.toLowerCase().contains(v);
    if (!pref && !last) return false;
  }
  return true;
}

class RankedProductSearchItem {
  const RankedProductSearchItem({required this.product, this.matchHint});

  final ProductModel product;
  final String? matchHint;
}

// Score weights (explicit for tuning / review).
const double _kNameExact = 1000;
const double _kNamePrefix = 520;
const double _kNameWord = 280;
const double _kNameSub = 160;
const double _kBarcodeExact = 820;
const double _kBarcodeCompact = 440;
const double _kCategory = 130;
const double _kCompany = 115;
const double _kSize = 100;
const double _kVendor = 125;
const double _kLocation = 120;
const double _kDescription = 55;
const double _kIdMatch = 90;
const double _kNumericField = 45;

/// Fuzzy match weights (scaled by string similarity 0–1).
const double _kFuzzyName = 150;
const double _kFuzzyBarcode = 200;
const double _kFuzzyCategory = 95;
const double _kFuzzyCompany = 85;
const double _kFuzzySize = 75;
const double _kFuzzyVendor = 90;
const double _kFuzzyLocation = 85;
const double _kFuzzyDescription = 62;

/// Each query token must reach at least this score (exact or fuzzy) to count.
const double _kMinPerTokenContribution = 36;

/// Minimum Levenshtein similarity (1 - d/maxLen) to accept a fuzzy hit.
const double _kFuzzyMinSimilarity = 0.58;

const int _kFuzzyMaxStringLen = 48;

bool _wordBoundaryContains(String haystack, String token) {
  if (token.isEmpty) return false;
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(token)) {
    return haystack.contains(token);
  }
  return RegExp(r'\b' + RegExp.escape(token) + r'\b').hasMatch(haystack);
}

/// Normalized similarity in \[0, 1\] using Levenshtein distance.
double levenshteinSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var sa = a.length > _kFuzzyMaxStringLen
      ? a.substring(0, _kFuzzyMaxStringLen)
      : a;
  var sb = b.length > _kFuzzyMaxStringLen
      ? b.substring(0, _kFuzzyMaxStringLen)
      : b;
  if (sa == sb) return 1;
  final d = levenshteinDistance(sa, sb);
  final maxLen = math.max(sa.length, sb.length);
  return maxLen == 0 ? 0 : (1.0 - d / maxLen).clamp(0.0, 1.0);
}

/// Classic Levenshtein edit distance (insert/delete/substitute).
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  var v0 = List<int>.generate(n + 1, (i) => i);
  var v1 = List<int>.filled(n + 1, 0);
  for (var i = 0; i < m; i++) {
    v1[0] = i + 1;
    for (var j = 0; j < n; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      v1[j + 1] = math.min(
        math.min(v1[j] + 1, v0[j + 1] + 1),
        v0[j] + cost,
      );
    }
    final t = v0;
    v0 = v1;
    v1 = t;
  }
  return v0[n];
}

Iterable<String> _alphanumericTokens(String lower) sync* {
  final re = RegExp(r'[a-z0-9]+');
  for (final m in re.allMatches(lower)) {
    final s = m.group(0)!;
    if (s.isNotEmpty) yield s;
  }
}

/// Best fuzzy score for [token] against a set of [candidates], scaled by [weight].
({double score, String hint}) _fuzzyAgainstCandidates(
  String token,
  Iterable<String> candidates,
  double weight,
  String hintLabel,
) {
  if (token.length < 2) return (score: 0, hint: '');
  double best = 0;
  for (final raw in candidates) {
    if (raw.length < 2) continue;
    final sim = levenshteinSimilarity(raw, token);
    if (sim >= _kFuzzyMinSimilarity) {
      final s = sim * weight;
      if (s > best) best = s;
    }
  }
  if (best <= 0) return (score: 0, hint: '');
  return (score: best, hint: hintLabel);
}

/// Typo-tolerant match across searchable fields when exact scoring is weak.
({double score, String hint}) _fuzzyTokenFields(ProductModel p, String token) {
  if (token.length < 2) return (score: 0, hint: '');

  double best = 0;
  var hint = '';

  void take(({double score, String hint}) r) {
    if (r.score > best) {
      best = r.score;
      hint = r.hint;
    }
  }

  final name = p.name.toLowerCase();
  take(
    _fuzzyAgainstCandidates(
      token,
      _alphanumericTokens(name),
      _kFuzzyName,
      'Name',
    ),
  );
  final nameCompact = compactProductToken(p.name);
  final tokCompact = compactProductToken(token);
  if (nameCompact.length >= 3 && tokCompact.length >= 3) {
    take(
      _fuzzyAgainstCandidates(
        tokCompact,
        [nameCompact],
        _kFuzzyName * 0.92,
        'Name',
      ),
    );
  }

  final bc = compactProductToken(p.barcode);
  if (bc.isNotEmpty && tokCompact.isNotEmpty) {
    if (bc.length >= 4 && tokCompact.length >= 4) {
      take(
        _fuzzyAgainstCandidates(
          tokCompact,
          [bc],
          _kFuzzyBarcode,
          'Barcode',
        ),
      );
    }
  }

  take(
    _fuzzyAgainstCandidates(
      token,
      _alphanumericTokens(p.categoryName.toLowerCase()),
      _kFuzzyCategory,
      'Category',
    ),
  );
  take(
    _fuzzyAgainstCandidates(
      token,
      _alphanumericTokens(p.company.toLowerCase()),
      _kFuzzyCompany,
      'Company',
    ),
  );
  take(
    _fuzzyAgainstCandidates(
      token,
      _alphanumericTokens(p.size.toLowerCase()),
      _kFuzzySize,
      'Sub-category',
    ),
  );
  take(
    _fuzzyAgainstCandidates(
      token,
      [
        ..._alphanumericTokens(p.preferredVendorName.toLowerCase()),
        ..._alphanumericTokens(p.lastVendorName.toLowerCase()),
      ],
      _kFuzzyVendor,
      'Vendor',
    ),
  );

  for (final loc in p.locationQuantities.keys) {
    take(
      _fuzzyAgainstCandidates(
        token,
        _alphanumericTokens(loc.toLowerCase()),
        _kFuzzyLocation,
        'Location',
      ),
    );
  }

  final desc = p.description.toLowerCase();
  if (desc.isNotEmpty) {
    final words = _alphanumericTokens(desc).take(80).toList();
    take(
      _fuzzyAgainstCandidates(
        token,
        words,
        _kFuzzyDescription,
        'Description',
      ),
    );
  }

  for (final vk in p.vendorPrices.keys) {
    take(
      _fuzzyAgainstCandidates(
        token,
        _alphanumericTokens(vk.toLowerCase()),
        _kFuzzyVendor,
        'Vendor price',
      ),
    );
  }

  return (score: best, hint: hint);
}

/// Single-token contribution: >0 if [token] matches somewhere on [p].
({double score, String hint}) _scoreToken(ProductModel p, String token) {
  if (token.isEmpty) return (score: 0, hint: '');

  double best = 0;
  var hint = '';

  void take(double s, String h) {
    if (s > best) {
      best = s;
      hint = h;
    }
  }

  final name = p.name.toLowerCase();
  if (name == token) {
    take(_kNameExact, 'Name');
  }
  if (name.startsWith(token)) {
    take(_kNamePrefix, 'Name');
  }
  if (_wordBoundaryContains(name, token)) {
    take(_kNameWord, 'Name');
  }
  if (name.contains(token)) {
    take(_kNameSub, 'Name');
  }

  final bc = p.barcode.toLowerCase();
  final bcCompact = compactProductToken(p.barcode);
  final tokCompact = compactProductToken(token);
  if (bc.isNotEmpty && bc == token) {
    take(_kBarcodeExact, 'Barcode');
  }
  if (tokCompact.isNotEmpty &&
      bcCompact.isNotEmpty &&
      (bcCompact == tokCompact || bcCompact.contains(tokCompact))) {
    take(_kBarcodeCompact, 'Barcode');
  }

  final cat = p.categoryName.toLowerCase();
  if (cat.contains(token)) take(_kCategory, 'Category');

  final comp = p.company.toLowerCase();
  if (comp.contains(token)) take(_kCompany, 'Company');

  final size = p.size.toLowerCase();
  if (size.contains(token)) take(_kSize, 'Sub-category');

  final pref = p.preferredVendorName.toLowerCase();
  final last = p.lastVendorName.toLowerCase();
  if (pref.contains(token) || last.contains(token)) {
    take(_kVendor, 'Vendor');
  }

  for (final loc in p.locationQuantities.keys) {
    if (loc.toLowerCase().contains(token)) {
      take(_kLocation, 'Location');
      break;
    }
  }

  final desc = p.description.toLowerCase();
  if (desc.contains(token)) take(_kDescription, 'Description');

  if (token.length >= 6 && p.id.toLowerCase().contains(token)) {
    take(_kIdMatch, 'ID');
  }

  final qtyStr = '${p.quantity}';
  final unit = p.unit.toLowerCase();
  if (qtyStr == token || (unit.isNotEmpty && '$qtyStr $unit'.contains(token))) {
    take(_kNumericField, 'Stock');
  }
  final cost = _priceTokens(p.costPrice);
  final sell = _priceTokens(p.sellingPrice);
  for (final pt in cost) {
    if (pt.contains(token) || token.contains(pt)) {
      take(_kNumericField, 'Cost');
      break;
    }
  }
  for (final pt in sell) {
    if (pt.contains(token) || token.contains(pt)) {
      take(_kNumericField, 'Price');
      break;
    }
  }

  for (final vk in p.vendorPrices.keys) {
    if (vk.toLowerCase().contains(token)) {
      take(_kVendor, 'Vendor price');
      break;
    }
  }

  if (best < _kMinPerTokenContribution) {
    final fz = _fuzzyTokenFields(p, token);
    if (fz.score > best) {
      best = fz.score;
      hint = fz.hint;
    }
  }

  return (score: best, hint: hint);
}

List<String> _priceTokens(double v) {
  if (v <= 0) return [];
  final s = v.toString().toLowerCase();
  final trimmed = s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
  return [s, trimmed];
}

/// Applies [parsed] to [catalog], ranks by relevance, returns top [limit] items.
List<RankedProductSearchItem> searchProductsRanked(
  List<ProductModel> catalog,
  String query, {
  int limit = 50,
  ParsedProductQuery? parsed,
}) {
  final pq = parsed ?? parseProductSearchQuery(query);
  final filtered = catalog
      .where((p) => productPassesSearchFilters(p, pq.filters))
      .toList();

  if (pq.freeTextTokens.isEmpty) {
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (filtered.length > limit) {
      return filtered
          .take(limit)
          .map((p) => RankedProductSearchItem(product: p))
          .toList();
    }
    return filtered.map((p) => RankedProductSearchItem(product: p)).toList();
  }

  final scored = <({ProductModel p, double score, String? hint})>[];
  for (final p in filtered) {
    String? bestHint;
    double bestPart = 0;
    double total = 0;
    var ok = true;
    for (final t in pq.freeTextTokens) {
      final r = _scoreToken(p, t);
      if (r.score < _kMinPerTokenContribution) {
        ok = false;
        break;
      }
      total += r.score;
      if (r.score > bestPart) {
        bestPart = r.score;
        bestHint = r.hint;
      }
    }
    if (!ok) continue;
    scored.add((p: p, score: total, hint: bestHint));
  }

  scored.sort((a, b) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
    return a.p.name.toLowerCase().compareTo(b.p.name.toLowerCase());
  });

  return scored
      .take(limit)
      .map((e) => RankedProductSearchItem(product: e.p, matchHint: e.hint))
      .toList();
}
