import '../models/invoice_model.dart';

/// User search input: lowercase, trim, strip `#`, remove spaces.
String normalizeInvoiceSearchQuery(String q) {
  var s = q.trim().toLowerCase();
  if (s.startsWith('#')) {
    s = s.substring(1).trim();
  }
  s = s.replaceAll(RegExp(r'\s+'), '');
  return s;
}

/// Alphanumeric only (for hyphen-insensitive matching).
String compactInvoiceKey(String normalized) {
  return normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

int? _trailingDigitsFromInvoiceNumber(String invoiceNumber) {
  final m = RegExp(r'(\d+)\s*$').firstMatch(invoiceNumber.trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

bool _digitsOnlyNormalized(String normalized) {
  return normalized.isNotEmpty && RegExp(r'^\d+$').hasMatch(normalized);
}

/// Whether [inv] matches free-text [query] (invoice # variants, party, amount, id).
bool invoiceMatchesSearch(InvoiceModel inv, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return false;

  final nq = normalizeInvoiceSearchQuery(query);
  if (nq.isEmpty) return false;

  final invNumLower = inv.invoiceNumber.toLowerCase().trim();
  final invNorm = normalizeInvoiceSearchQuery(inv.invoiceNumber);
  final invCompact = compactInvoiceKey(invNorm);
  final qCompact = compactInvoiceKey(nq);

  if (invNorm.contains(nq) || invNumLower.contains(nq)) return true;
  if (qCompact.isNotEmpty && invCompact.contains(qCompact)) return true;

  if (_digitsOnlyNormalized(nq)) {
    final qVal = int.tryParse(nq);
    final suffix = _trailingDigitsFromInvoiceNumber(inv.invoiceNumber);
    if (qVal != null && suffix != null && suffix == qVal) return true;
  }

  final party = inv.partyName.toLowerCase();
  if (party.contains(nq)) return true;

  final phoneCompact = inv.customerPhone
      .replaceAll(RegExp(r'\s'), '')
      .toLowerCase();
  final qPhone = nq.replaceAll(RegExp(r'\s'), '');
  if (phoneCompact.isNotEmpty &&
      qPhone.isNotEmpty &&
      phoneCompact.contains(qPhone)) {
    return true;
  }

  if (inv.grandTotal.toString().contains(trimmed)) return true;

  if (nq.length >= 6 && inv.id.toLowerCase().contains(nq)) return true;

  return false;
}

/// Stock transaction reasons use `INV #INV-0001` or `Cancelled INV #INV-0001`.
String? invoiceNumberFromStockReason(String reason) {
  final m = RegExp(
    r'(?:Cancelled\s+)?INV\s*#\s*(\S+)',
    caseSensitive: false,
  ).firstMatch(reason.trim());
  return m?.group(1);
}
