import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// The heads an operating expense can sit under.
///
/// A fixed list rather than free text, because the whole point is to compare
/// this month's rent with last month's: two spellings of "electricity" would
/// make the summary — and any budget built on it — silently wrong. [other]
/// carries a free-text label for the long tail.
enum ExpenseCategory {
  rent,
  salaries,
  utilities,
  freightOut,
  marketing,
  repairs,
  professionalFees,
  travel,
  insurance,
  bankCharges,
  taxes,
  other,
}

/// How an expense was settled.
enum ExpenseStatus { unpaid, paid }

/// One operating cost, dated and categorised.
class ExpenseModel {
  final String id;

  /// Your own voucher or bill number.
  final String reference;

  final ExpenseCategory category;

  /// Free-text head, used when [category] is [ExpenseCategory.other].
  final String customCategory;

  /// Optional supplier. Kept as a plain pair rather than a hard reference: rent
  /// and salaries have a payee that is not in the vendor list.
  final String vendorId;
  final String vendorName;

  /// The amount before tax.
  final double amount;

  /// Recoverable tax on the expense, held apart from [amount] so the tax
  /// summary's input tax and the P&L's cost are not the same number.
  final double taxAmount;

  final ExpenseStatus status;
  final String paymentMethod;
  final DateTime expenseDate;
  final DateTime? paidAt;
  final String notes;

  /// Set when the expense is one of a recurring set the user keeps re-entering;
  /// purely a label, since nothing here generates them.
  final bool isRecurring;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExpenseModel({
    required this.id,
    this.reference = '',
    this.category = ExpenseCategory.other,
    this.customCategory = '',
    this.vendorId = '',
    this.vendorName = '',
    this.amount = 0,
    this.taxAmount = 0,
    this.status = ExpenseStatus.unpaid,
    this.paymentMethod = '',
    required this.expenseDate,
    this.paidAt,
    this.notes = '',
    this.isRecurring = false,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// What actually leaves the bank.
  double get total => amount + taxAmount;

  bool get isPaid => status == ExpenseStatus.paid;

  /// The head as a user reads it.
  String get categoryLabel => category == ExpenseCategory.other &&
          customCategory.trim().isNotEmpty
      ? customCategory.trim()
      : categoryLabelOf(category);

  /// Stable key for grouping: the enum name, or the custom label lower-cased so
  /// "Cleaning" and "cleaning" land in one bucket.
  String get categoryKey => category == ExpenseCategory.other &&
          customCategory.trim().isNotEmpty
      ? 'other:${customCategory.trim().toLowerCase()}'
      : categoryToString(category);

  static String categoryLabelOf(ExpenseCategory c) => switch (c) {
    ExpenseCategory.rent => 'Rent & premises',
    ExpenseCategory.salaries => 'Salaries & wages',
    ExpenseCategory.utilities => 'Utilities',
    ExpenseCategory.freightOut => 'Freight out',
    ExpenseCategory.marketing => 'Marketing',
    ExpenseCategory.repairs => 'Repairs & maintenance',
    ExpenseCategory.professionalFees => 'Professional fees',
    ExpenseCategory.travel => 'Travel',
    ExpenseCategory.insurance => 'Insurance',
    ExpenseCategory.bankCharges => 'Bank charges',
    ExpenseCategory.taxes => 'Taxes & duties',
    ExpenseCategory.other => 'Other',
  };

  static ExpenseCategory categoryFromString(String s) =>
      ExpenseCategory.values.firstWhere(
        (c) => c.name == s,
        orElse: () => ExpenseCategory.other,
      );

  static String categoryToString(ExpenseCategory c) => c.name;

  static ExpenseStatus statusFromString(String s) =>
      s == 'paid' ? ExpenseStatus.paid : ExpenseStatus.unpaid;

  static String statusToString(ExpenseStatus s) => s.name;

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String docId) =>
      ExpenseModel(
        id: docId,
        reference: safeString(map['reference']),
        category: categoryFromString(safeString(map['category'], 'other')),
        customCategory: safeString(map['customCategory']),
        vendorId: safeString(map['vendorId']),
        vendorName: safeString(map['vendorName']),
        amount: safeDouble(map['amount']),
        taxAmount: safeDouble(map['taxAmount']),
        status: statusFromString(safeString(map['status'], 'unpaid')),
        paymentMethod: safeString(map['paymentMethod']),
        expenseDate: safeTimestamp(map['expenseDate']),
        paidAt: map['paidAt'] == null ? null : safeTimestamp(map['paidAt']),
        notes: safeString(map['notes']),
        isRecurring: safeBool(map['isRecurring']),
        createdBy: safeString(map['createdBy']),
        createdByName: safeString(map['createdByName']),
        createdAt: safeTimestamp(map['createdAt']),
        updatedAt: safeTimestamp(map['updatedAt']),
      );

  Map<String, dynamic> toMap() => {
    'reference': reference,
    'category': categoryToString(category),
    'customCategory': customCategory,
    'vendorId': vendorId,
    'vendorName': vendorName,
    'amount': amount,
    'taxAmount': taxAmount,
    'total': total,
    'status': statusToString(status),
    'paymentMethod': paymentMethod,
    'expenseDate': Timestamp.fromDate(expenseDate),
    if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
    'notes': notes,
    'isRecurring': isRecurring,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  ExpenseModel copyWith({
    String? id,
    String? reference,
    ExpenseCategory? category,
    String? customCategory,
    String? vendorId,
    String? vendorName,
    double? amount,
    double? taxAmount,
    ExpenseStatus? status,
    String? paymentMethod,
    DateTime? expenseDate,
    DateTime? paidAt,
    String? notes,
    bool? isRecurring,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ExpenseModel(
    id: id ?? this.id,
    reference: reference ?? this.reference,
    category: category ?? this.category,
    customCategory: customCategory ?? this.customCategory,
    vendorId: vendorId ?? this.vendorId,
    vendorName: vendorName ?? this.vendorName,
    amount: amount ?? this.amount,
    taxAmount: taxAmount ?? this.taxAmount,
    status: status ?? this.status,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    expenseDate: expenseDate ?? this.expenseDate,
    paidAt: paidAt ?? this.paidAt,
    notes: notes ?? this.notes,
    isRecurring: isRecurring ?? this.isRecurring,
    createdBy: createdBy ?? this.createdBy,
    createdByName: createdByName ?? this.createdByName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
