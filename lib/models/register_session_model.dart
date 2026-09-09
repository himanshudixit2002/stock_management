import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/parse_helpers.dart';

/// Whether a till shift is still running.
enum RegisterSessionStatus { open, closed }

/// Cash added to or taken out of the drawer during a shift, other than by a
/// sale: a float top-up, a safe drop, a petty-cash payout.
class CashMovement {
  final String id;

  /// Positive adds to the drawer, negative takes out of it. One signed field
  /// rather than a type plus a magnitude, so the expected-cash sum cannot
  /// disagree with the list a user reads.
  final double amount;

  final String reason;
  final String userId;
  final String userName;
  final DateTime at;

  const CashMovement({
    required this.id,
    required this.amount,
    this.reason = '',
    this.userId = '',
    this.userName = '',
    required this.at,
  });

  bool get isPayout => amount < 0;

  factory CashMovement.fromMap(Map<String, dynamic> map) => CashMovement(
    id: safeString(map['id']),
    amount: safeDouble(map['amount']),
    reason: safeString(map['reason']),
    userId: safeString(map['userId']),
    userName: safeString(map['userName']),
    at: safeTimestamp(map['at']),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'amount': amount,
    'reason': reason,
    'userId': userId,
    'userName': userName,
    'at': Timestamp.fromDate(at),
  };
}

/// One till shift: opened with a float, closed with a count.
///
/// The counted figure is entered before the app shows what it expected — a
/// blind close. A count taken with the expected number on screen is not a
/// count, it is a confirmation, and it hides exactly the discrepancies this
/// exists to find. That is why [countedCash] and [expectedCash] are stored
/// separately rather than one being derived at read time.
class RegisterSessionModel {
  final String id;

  /// Which till this is. Free text, matched case-insensitively through
  /// [registerKey] so "Counter 1" and "counter 1" are one register.
  final String registerName;

  final RegisterSessionStatus status;
  final double openingFloat;
  final List<CashMovement> movements;

  /// What the drawer should hold at close: float + cash takings + movements.
  /// Stamped at close so a later refund or a voided invoice cannot rewrite the
  /// history of a shift that has already been signed off.
  final double expectedCash;

  /// What the operator actually counted.
  final double countedCash;

  /// Takings by payment method over the shift, stamped at close.
  final Map<String, double> takingsByMethod;

  final int invoiceCount;
  final double salesTotal;

  final String openedBy;
  final String openedByName;
  final DateTime openedAt;
  final String closedBy;
  final String closedByName;
  final DateTime? closedAt;
  final String notes;

  RegisterSessionModel({
    required this.id,
    required this.registerName,
    this.status = RegisterSessionStatus.open,
    this.openingFloat = 0,
    this.movements = const [],
    this.expectedCash = 0,
    this.countedCash = 0,
    this.takingsByMethod = const {},
    this.invoiceCount = 0,
    this.salesTotal = 0,
    this.openedBy = '',
    this.openedByName = '',
    required this.openedAt,
    this.closedBy = '',
    this.closedByName = '',
    this.closedAt,
    this.notes = '',
  });

  /// Case- and space-insensitive identity of the till.
  static String keyFor(String registerName) {
    final collapsed = registerName.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? 'main' : collapsed.toLowerCase();
  }

  String get registerKey => keyFor(registerName);

  bool get isOpen => status == RegisterSessionStatus.open;

  /// Net of every non-sale cash movement.
  double get movementTotal => movements.fold(0.0, (acc, m) => acc + m.amount);

  double get cashDrops =>
      movements.where((m) => m.amount < 0).fold(0.0, (acc, m) => acc - m.amount);

  double get cashAdded =>
      movements.where((m) => m.amount > 0).fold(0.0, (acc, m) => acc + m.amount);

  /// Counted minus expected. Negative is a shortfall, positive an overage.
  double get variance => countedCash - expectedCash;

  bool get isBalanced => variance.abs() < 0.01;

  Duration get duration =>
      (closedAt ?? DateTime.now()).difference(openedAt);

  String get statusLabel => isOpen ? 'Open' : 'Closed';

  static RegisterSessionStatus statusFromString(String s) =>
      s == 'closed' ? RegisterSessionStatus.closed : RegisterSessionStatus.open;

  static String statusToString(RegisterSessionStatus s) => s.name;

  factory RegisterSessionModel.fromMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    final rawMovements = map['movements'];
    final rawTakings = map['takingsByMethod'];
    return RegisterSessionModel(
      id: docId,
      registerName: safeString(map['registerName'], 'Main'),
      status: statusFromString(safeString(map['status'], 'open')),
      openingFloat: safeDouble(map['openingFloat']),
      movements: rawMovements is List
          ? rawMovements
                .whereType<Map>()
                .map((e) => CashMovement.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      expectedCash: safeDouble(map['expectedCash']),
      countedCash: safeDouble(map['countedCash']),
      takingsByMethod: rawTakings is Map
          ? {
              for (final entry in rawTakings.entries)
                safeString(entry.key): safeDouble(entry.value),
            }
          : const {},
      invoiceCount: safeInt(map['invoiceCount']),
      salesTotal: safeDouble(map['salesTotal']),
      openedBy: safeString(map['openedBy']),
      openedByName: safeString(map['openedByName']),
      openedAt: safeTimestamp(map['openedAt']),
      closedBy: safeString(map['closedBy']),
      closedByName: safeString(map['closedByName']),
      closedAt: map['closedAt'] == null ? null : safeTimestamp(map['closedAt']),
      notes: safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
    // Marks this document as a shift rather than the register lock kept in the
    // same collection; the stream filters on it.
    'docType': 'session',
    'registerName': registerName,
    'registerKey': registerKey,
    'status': statusToString(status),
    'openingFloat': openingFloat,
    'movements': movements.map((m) => m.toMap()).toList(),
    'expectedCash': expectedCash,
    'countedCash': countedCash,
    'takingsByMethod': takingsByMethod,
    'invoiceCount': invoiceCount,
    'salesTotal': salesTotal,
    'openedBy': openedBy,
    'openedByName': openedByName,
    'openedAt': Timestamp.fromDate(openedAt),
    'closedBy': closedBy,
    'closedByName': closedByName,
    if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    'notes': notes,
  };

  RegisterSessionModel copyWith({
    String? id,
    String? registerName,
    RegisterSessionStatus? status,
    double? openingFloat,
    List<CashMovement>? movements,
    double? expectedCash,
    double? countedCash,
    Map<String, double>? takingsByMethod,
    int? invoiceCount,
    double? salesTotal,
    String? openedBy,
    String? openedByName,
    DateTime? openedAt,
    String? closedBy,
    String? closedByName,
    DateTime? closedAt,
    String? notes,
  }) => RegisterSessionModel(
    id: id ?? this.id,
    registerName: registerName ?? this.registerName,
    status: status ?? this.status,
    openingFloat: openingFloat ?? this.openingFloat,
    movements: movements ?? this.movements,
    expectedCash: expectedCash ?? this.expectedCash,
    countedCash: countedCash ?? this.countedCash,
    takingsByMethod: takingsByMethod ?? this.takingsByMethod,
    invoiceCount: invoiceCount ?? this.invoiceCount,
    salesTotal: salesTotal ?? this.salesTotal,
    openedBy: openedBy ?? this.openedBy,
    openedByName: openedByName ?? this.openedByName,
    openedAt: openedAt ?? this.openedAt,
    closedBy: closedBy ?? this.closedBy,
    closedByName: closedByName ?? this.closedByName,
    closedAt: closedAt ?? this.closedAt,
    notes: notes ?? this.notes,
  );
}
