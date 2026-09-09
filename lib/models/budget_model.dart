import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// How long a budget covers.
enum BudgetPeriod { month, quarter, year }

/// What a budget line measures. Each maps to actuals the workspace already
/// records, which is the constraint that shaped this list: a line nothing can
/// measure is a wish, not a budget.
enum BudgetLineType {
  /// Sales invoices raised in the period.
  revenue,

  /// Purchase orders raised in the period.
  purchases,

  /// Operating expenses in the period, optionally narrowed to one head.
  expense,
}

/// One budgeted figure.
class BudgetLine {
  final BudgetLineType type;

  /// For [BudgetLineType.expense], the [ExpenseModel.categoryKey] this line
  /// budgets — empty means every expense head together.
  final String categoryKey;

  final String label;
  final double amount;

  const BudgetLine({
    required this.type,
    this.categoryKey = '',
    this.label = '',
    this.amount = 0,
  });

  /// Identity within a budget: two lines with the same type and head are the
  /// same line, which is what stops a budget holding "Rent 20,000" twice.
  String get key => '${type.name}:$categoryKey';

  bool get isSpend => type != BudgetLineType.revenue;

  String get displayLabel => label.trim().isNotEmpty
      ? label.trim()
      : switch (type) {
          BudgetLineType.revenue => 'Revenue',
          BudgetLineType.purchases => 'Purchases',
          BudgetLineType.expense =>
            categoryKey.isEmpty ? 'Operating expenses' : categoryKey,
        };

  factory BudgetLine.fromMap(Map<String, dynamic> map) => BudgetLine(
    type: typeFromString(safeString(map['type'], 'expense')),
    categoryKey: safeString(map['categoryKey']),
    label: safeString(map['label']),
    amount: safeDouble(map['amount']),
  );

  Map<String, dynamic> toMap() => {
    'type': typeToString(type),
    'categoryKey': categoryKey,
    'label': label,
    'amount': amount,
  };

  BudgetLine copyWith({
    BudgetLineType? type,
    String? categoryKey,
    String? label,
    double? amount,
  }) => BudgetLine(
    type: type ?? this.type,
    categoryKey: categoryKey ?? this.categoryKey,
    label: label ?? this.label,
    amount: amount ?? this.amount,
  );

  static BudgetLineType typeFromString(String s) => switch (s) {
    'revenue' => BudgetLineType.revenue,
    'purchases' => BudgetLineType.purchases,
    _ => BudgetLineType.expense,
  };

  static String typeToString(BudgetLineType t) => t.name;

  static String typeLabelOf(BudgetLineType t) => switch (t) {
    BudgetLineType.revenue => 'Revenue',
    BudgetLineType.purchases => 'Purchases',
    BudgetLineType.expense => 'Expense',
  };
}

/// A period plan: what the workspace intends to earn and spend.
class BudgetModel {
  final String id;
  final String name;
  final BudgetPeriod period;

  /// First day of the period. Stored rather than parsed out of a label, so the
  /// variance service never has to guess what "Q3" means to this workspace.
  final DateTime periodStart;

  final List<BudgetLine> lines;
  final bool isActive;
  final String notes;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  BudgetModel({
    required this.id,
    required this.name,
    this.period = BudgetPeriod.month,
    required this.periodStart,
    this.lines = const [],
    this.isActive = true,
    this.notes = '',
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Exclusive end of the period.
  DateTime get periodEnd => switch (period) {
    BudgetPeriod.month => DateTime(periodStart.year, periodStart.month + 1, 1),
    BudgetPeriod.quarter => DateTime(periodStart.year, periodStart.month + 3, 1),
    BudgetPeriod.year => DateTime(periodStart.year + 1, periodStart.month, 1),
  };

  bool covers(DateTime date) =>
      !date.isBefore(periodStart) && date.isBefore(periodEnd);

  bool get isCurrent => covers(DateTime.now());

  double get totalRevenueBudget => lines
      .where((l) => l.type == BudgetLineType.revenue)
      .fold(0.0, (acc, l) => acc + l.amount);

  double get totalSpendBudget =>
      lines.where((l) => l.isSpend).fold(0.0, (acc, l) => acc + l.amount);

  /// Share of the period already elapsed, 0..1. The reason a budget report can
  /// say "60% spent" and still call it a problem: in month two of a year, it is.
  double get elapsedShare {
    final now = DateTime.now();
    if (now.isBefore(periodStart)) return 0;
    if (!now.isBefore(periodEnd)) return 1;
    final total = periodEnd.difference(periodStart).inSeconds;
    if (total <= 0) return 1;
    return now.difference(periodStart).inSeconds / total;
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get periodLabel => switch (period) {
    BudgetPeriod.month =>
      '${_monthNames[periodStart.month - 1]} ${periodStart.year}',
    BudgetPeriod.quarter =>
      'Q${((periodStart.month - 1) ~/ 3) + 1} ${periodStart.year}',
    BudgetPeriod.year => '${periodStart.year}',
  };

  static String periodLabelOf(BudgetPeriod p) => switch (p) {
    BudgetPeriod.month => 'Monthly',
    BudgetPeriod.quarter => 'Quarterly',
    BudgetPeriod.year => 'Yearly',
  };

  static BudgetPeriod periodFromString(String s) => switch (s) {
    'quarter' => BudgetPeriod.quarter,
    'year' => BudgetPeriod.year,
    _ => BudgetPeriod.month,
  };

  static String periodToString(BudgetPeriod p) => p.name;

  /// Normalises [date] to the first day of the period it falls in, so two
  /// budgets for the same month cannot differ by the day somebody picked.
  static DateTime normalizeStart(DateTime date, BudgetPeriod period) =>
      switch (period) {
        BudgetPeriod.month => DateTime(date.year, date.month, 1),
        BudgetPeriod.quarter =>
          DateTime(date.year, (((date.month - 1) ~/ 3) * 3) + 1, 1),
        BudgetPeriod.year => DateTime(date.year, 1, 1),
      };

  factory BudgetModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawLines = map['lines'];
    return BudgetModel(
      id: docId,
      name: safeString(map['name']),
      period: periodFromString(safeString(map['period'], 'month')),
      periodStart: safeTimestamp(map['periodStart']),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map((e) => BudgetLine.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      isActive: safeBool(map['isActive'], true),
      notes: safeString(map['notes']),
      createdBy: safeString(map['createdBy']),
      createdByName: safeString(map['createdByName']),
      createdAt: safeTimestamp(map['createdAt']),
      updatedAt: safeTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'period': periodToString(period),
    'periodStart': Timestamp.fromDate(periodStart),
    'lines': lines.map((l) => l.toMap()).toList(),
    'isActive': isActive,
    'notes': notes,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  BudgetModel copyWith({
    String? id,
    String? name,
    BudgetPeriod? period,
    DateTime? periodStart,
    List<BudgetLine>? lines,
    bool? isActive,
    String? notes,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BudgetModel(
    id: id ?? this.id,
    name: name ?? this.name,
    period: period ?? this.period,
    periodStart: periodStart ?? this.periodStart,
    lines: lines ?? this.lines,
    isActive: isActive ?? this.isActive,
    notes: notes ?? this.notes,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
