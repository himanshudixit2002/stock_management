import '../models/invoice_model.dart';

/// Standard receivables/payables ageing buckets.
enum AgingBucket { current, days30, days60, days90, days90Plus }

extension AgingBucketLabel on AgingBucket {
  String get label => switch (this) {
    AgingBucket.current => 'Not due',
    AgingBucket.days30 => '1–30 days',
    AgingBucket.days60 => '31–60 days',
    AgingBucket.days90 => '61–90 days',
    AgingBucket.days90Plus => '90+ days',
  };
}

/// Everything owed by (or to) one party, split into ageing buckets.
class PartyAging {
  final String partyId;
  final String partyName;
  final Map<AgingBucket, double> buckets;
  final List<InvoiceModel> invoices;

  const PartyAging({
    required this.partyId,
    required this.partyName,
    required this.buckets,
    required this.invoices,
  });

  double get total =>
      buckets.values.fold<double>(0, (sum, value) => sum + value);

  double amountIn(AgingBucket bucket) => buckets[bucket] ?? 0;
}

/// Groups outstanding invoices into ageing buckets per party.
///
/// Receivables and payables are computed separately — netting customer debt
/// against supplier debt (which the old totalOutstanding did) hides both.
class AgingService {
  const AgingService();

  static AgingBucket bucketFor(int daysOverdue) {
    if (daysOverdue <= 0) return AgingBucket.current;
    if (daysOverdue <= 30) return AgingBucket.days30;
    if (daysOverdue <= 60) return AgingBucket.days60;
    if (daysOverdue <= 90) return AgingBucket.days90;
    return AgingBucket.days90Plus;
  }

  /// [sales] true builds receivables (customer invoices), false builds
  /// payables (supplier bills).
  List<PartyAging> build(
    List<InvoiceModel> invoices, {
    required bool sales,
    required DateTime asOf,
  }) {
    final byParty = <String, List<InvoiceModel>>{};

    for (final inv in invoices) {
      if (inv.isSales != sales) continue;
      // Cancelled documents owe nothing; drafts are not yet a claim.
      if (inv.isCancelled || inv.isDraft) continue;
      if (inv.amountDue <= 0.01) continue;

      final key = inv.partyId.isNotEmpty ? inv.partyId : inv.partyName;
      byParty.putIfAbsent(key, () => []).add(inv);
    }

    final result = <PartyAging>[];
    byParty.forEach((partyId, list) {
      final buckets = <AgingBucket, double>{};
      for (final inv in list) {
        final days = asOf.difference(inv.dueDate).inDays;
        final bucket = bucketFor(days);
        buckets[bucket] = (buckets[bucket] ?? 0) + inv.amountDue;
      }
      list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      result.add(
        PartyAging(
          partyId: partyId,
          partyName: list.first.partyName.isNotEmpty
              ? list.first.partyName
              : 'Unnamed',
          buckets: buckets,
          invoices: list,
        ),
      );
    });

    result.sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  /// Column totals across every party.
  Map<AgingBucket, double> totals(List<PartyAging> rows) {
    final out = <AgingBucket, double>{};
    for (final row in rows) {
      row.buckets.forEach((bucket, value) {
        out[bucket] = (out[bucket] ?? 0) + value;
      });
    }
    return out;
  }
}
