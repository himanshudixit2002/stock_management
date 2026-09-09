import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';
import 'invoice_model.dart';

/// How often a schedule bills.
enum RecurrenceCadence { weekly, fortnightly, monthly, quarterly, yearly }

/// Lifecycle of a billing schedule.
enum RecurringInvoiceStatus { active, paused, ended }

/// A saved invoice template plus a cadence.
///
/// Generation is explicit — a person presses "Generate due" — because there is
/// no server-side scheduler in this app, and inventing one that runs on
/// whichever client happens to be open would bill customers at random. What the
/// schedule does guarantee is that generating twice cannot double-bill:
/// [nextRunAt] advances as part of the same write that creates the invoice.
class RecurringInvoiceModel {
  final String id;

  /// Human name for the schedule, e.g. "Acme — monthly retainer".
  final String title;

  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;

  final List<InvoiceItem> items;
  final double discountPercent;
  final double discountAmount;
  final String taxLabel;
  final String notes;
  final String termsText;

  /// Days from issue to due date on each generated invoice.
  final int paymentTermDays;

  /// Status generated invoices are created in. Draft by default so a person
  /// still reviews before it goes out.
  final InvoiceStatus issueStatus;

  final RecurrenceCadence cadence;
  final RecurringInvoiceStatus status;

  final DateTime startDate;

  /// Optional stop date. A schedule past its end is [ended] and generates
  /// nothing further.
  final DateTime? endDate;

  /// Optional cap on how many invoices this schedule ever produces.
  final int maxOccurrences;

  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final int generatedCount;

  /// Invoice ids this schedule has produced, most recent last. Capped so a
  /// long-lived schedule cannot grow the document without bound.
  final List<String> generatedInvoiceIds;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecurringInvoiceModel({
    required this.id,
    this.title = '',
    required this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.items = const [],
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.taxLabel = 'GST',
    this.notes = '',
    this.termsText = '',
    this.paymentTermDays = 15,
    this.issueStatus = InvoiceStatus.draft,
    this.cadence = RecurrenceCadence.monthly,
    this.status = RecurringInvoiceStatus.active,
    required this.startDate,
    this.endDate,
    this.maxOccurrences = 0,
    required this.nextRunAt,
    this.lastRunAt,
    this.generatedCount = 0,
    this.generatedInvoiceIds = const [],
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// How many generated invoice ids the document keeps.
  static const int historyLimit = 50;

  bool get isActive => status == RecurringInvoiceStatus.active;

  bool get hasReachedCap =>
      maxOccurrences > 0 && generatedCount >= maxOccurrences;

  bool get hasPassedEndDate =>
      endDate != null && nextRunAt.isAfter(endDate!);

  /// True when a run is owed as of [asOf].
  ///
  /// Compared on whole days so a schedule due "today" is due from midnight,
  /// not from the minute it was created a month ago.
  bool isDue({DateTime? asOf}) {
    if (!isActive || hasReachedCap || hasPassedEndDate) return false;
    final now = asOf ?? DateTime.now();
    final due = DateTime(nextRunAt.year, nextRunAt.month, nextRunAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return !due.isAfter(today);
  }

  /// Days until the next run; negative when overdue.
  int daysUntilDue({DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final due = DateTime(nextRunAt.year, nextRunAt.month, nextRunAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return due.difference(today).inDays;
  }

  /// The run date after [from] for this schedule's cadence.
  DateTime advanceFrom(DateTime from) => advance(from, cadence);

  /// [from] moved forward by one [cadence] period.
  ///
  /// Month arithmetic clamps the day rather than overflowing: a schedule that
  /// starts on the 31st bills on the 28th/30th in shorter months instead of
  /// silently jumping into the following month, which is what
  /// `DateTime(y, m + 1, 31)` would do.
  static DateTime advance(DateTime from, RecurrenceCadence cadence) {
    switch (cadence) {
      case RecurrenceCadence.weekly:
        return from.add(const Duration(days: 7));
      case RecurrenceCadence.fortnightly:
        return from.add(const Duration(days: 14));
      case RecurrenceCadence.monthly:
        return _addMonths(from, 1);
      case RecurrenceCadence.quarterly:
        return _addMonths(from, 3);
      case RecurrenceCadence.yearly:
        return _addMonths(from, 12);
    }
  }

  static DateTime _addMonths(DateTime from, int months) {
    final totalMonths = from.month - 1 + months;
    final year = from.year + (totalMonths ~/ 12);
    final month = totalMonths % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return DateTime(year, month, day, from.hour, from.minute);
  }

  String get cadenceLabel => cadenceLabelOf(cadence);

  static String cadenceLabelOf(RecurrenceCadence c) => switch (c) {
    RecurrenceCadence.weekly => 'Weekly',
    RecurrenceCadence.fortnightly => 'Every 2 weeks',
    RecurrenceCadence.monthly => 'Monthly',
    RecurrenceCadence.quarterly => 'Quarterly',
    RecurrenceCadence.yearly => 'Yearly',
  };

  static RecurrenceCadence cadenceFromString(String s) => switch (s) {
    'weekly' => RecurrenceCadence.weekly,
    'fortnightly' => RecurrenceCadence.fortnightly,
    'quarterly' => RecurrenceCadence.quarterly,
    'yearly' => RecurrenceCadence.yearly,
    _ => RecurrenceCadence.monthly,
  };

  static String cadenceToString(RecurrenceCadence c) => switch (c) {
    RecurrenceCadence.weekly => 'weekly',
    RecurrenceCadence.fortnightly => 'fortnightly',
    RecurrenceCadence.monthly => 'monthly',
    RecurrenceCadence.quarterly => 'quarterly',
    RecurrenceCadence.yearly => 'yearly',
  };

  String get statusLabel => switch (status) {
    RecurringInvoiceStatus.active => 'Active',
    RecurringInvoiceStatus.paused => 'Paused',
    RecurringInvoiceStatus.ended => 'Ended',
  };

  static RecurringInvoiceStatus statusFromString(String s) => switch (s) {
    'paused' => RecurringInvoiceStatus.paused,
    'ended' => RecurringInvoiceStatus.ended,
    _ => RecurringInvoiceStatus.active,
  };

  static String statusToString(RecurringInvoiceStatus s) => switch (s) {
    RecurringInvoiceStatus.active => 'active',
    RecurringInvoiceStatus.paused => 'paused',
    RecurringInvoiceStatus.ended => 'ended',
  };

  static InvoiceStatus _issueStatusFromString(String s) =>
      s == 'sent' ? InvoiceStatus.sent : InvoiceStatus.draft;

  factory RecurringInvoiceModel.fromMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    final rawItems = map['items'];
    final rawIds = map['generatedInvoiceIds'];
    return RecurringInvoiceModel(
      id: docId,
      title: safeString(map['title']),
      customerId: safeString(map['customerId']),
      customerName: safeString(map['customerName']),
      customerPhone: safeString(map['customerPhone']),
      customerAddress: safeString(map['customerAddress']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => InvoiceItem.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      discountPercent: safeDouble(map['discountPercent']),
      discountAmount: safeDouble(map['discountAmount']),
      taxLabel: safeString(map['taxLabel'], 'GST'),
      notes: safeString(map['notes']),
      termsText: safeString(map['termsText']),
      paymentTermDays: safeInt(map['paymentTermDays'], 15),
      issueStatus: _issueStatusFromString(safeString(map['issueStatus'], 'draft')),
      cadence: cadenceFromString(safeString(map['cadence'], 'monthly')),
      status: statusFromString(safeString(map['status'], 'active')),
      startDate: safeTimestamp(map['startDate']),
      endDate: map['endDate'] == null ? null : safeTimestamp(map['endDate']),
      maxOccurrences: safeInt(map['maxOccurrences']),
      nextRunAt: safeTimestamp(map['nextRunAt']),
      lastRunAt: map['lastRunAt'] == null ? null : safeTimestamp(map['lastRunAt']),
      generatedCount: safeInt(map['generatedCount']),
      generatedInvoiceIds: rawIds is List
          ? rawIds.whereType<String>().toList()
          : const [],
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerAddress': customerAddress,
    'items': items.map((i) => i.toMap()).toList(),
    'discountPercent': discountPercent,
    'discountAmount': discountAmount,
    'taxLabel': taxLabel,
    'notes': notes,
    'termsText': termsText,
    'paymentTermDays': paymentTermDays,
    'issueStatus': issueStatus == InvoiceStatus.sent ? 'sent' : 'draft',
    'cadence': cadenceToString(cadence),
    'status': statusToString(status),
    'startDate': Timestamp.fromDate(startDate),
    if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
    'maxOccurrences': maxOccurrences,
    'nextRunAt': Timestamp.fromDate(nextRunAt),
    if (lastRunAt != null) 'lastRunAt': Timestamp.fromDate(lastRunAt!),
    'generatedCount': generatedCount,
    'generatedInvoiceIds': generatedInvoiceIds,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  RecurringInvoiceModel copyWith({
    String? id,
    String? title,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    List<InvoiceItem>? items,
    double? discountPercent,
    double? discountAmount,
    String? taxLabel,
    String? notes,
    String? termsText,
    int? paymentTermDays,
    InvoiceStatus? issueStatus,
    RecurrenceCadence? cadence,
    RecurringInvoiceStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    int? maxOccurrences,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    int? generatedCount,
    List<String>? generatedInvoiceIds,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => RecurringInvoiceModel(
    id: id ?? this.id,
    title: title ?? this.title,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    customerAddress: customerAddress ?? this.customerAddress,
    items: items ?? this.items,
    discountPercent: discountPercent ?? this.discountPercent,
    discountAmount: discountAmount ?? this.discountAmount,
    taxLabel: taxLabel ?? this.taxLabel,
    notes: notes ?? this.notes,
    termsText: termsText ?? this.termsText,
    paymentTermDays: paymentTermDays ?? this.paymentTermDays,
    issueStatus: issueStatus ?? this.issueStatus,
    cadence: cadence ?? this.cadence,
    status: status ?? this.status,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    maxOccurrences: maxOccurrences ?? this.maxOccurrences,
    nextRunAt: nextRunAt ?? this.nextRunAt,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    generatedCount: generatedCount ?? this.generatedCount,
    generatedInvoiceIds: generatedInvoiceIds ?? this.generatedInvoiceIds,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
