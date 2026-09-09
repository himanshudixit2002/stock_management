import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/invoice_model.dart';
import '../models/recurring_invoice_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';
import '../utils/invoice_totals.dart';

/// The outcome of a "generate everything due" run.
class RecurringRunResult {
  const RecurringRunResult({
    required this.generated,
    required this.skipped,
    required this.failures,
  });

  /// Invoice ids created by this run.
  final List<String> generated;

  /// Schedules that turned out not to be due after all — someone else got
  /// there first, which is a normal outcome rather than an error.
  final int skipped;

  /// Schedule titles that could not be generated, with the reason.
  final Map<String, String> failures;

  int get count => generated.length;

  bool get isClean => failures.isEmpty;
}

/// Recurring billing schedules.
class RecurringInvoiceProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<RecurringInvoiceModel> _schedules = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<RecurringInvoiceModel> get schedules => _schedules;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Schedules owed an invoice right now.
  List<RecurringInvoiceModel> get due =>
      _schedules.where((s) => s.isDue()).toList(growable: false);

  /// Value of everything currently due, so the banner can say what generating
  /// would actually bill.
  double get dueValue => due.fold(0.0, (acc, s) => acc + _totalOf(s));

  RecurringInvoiceModel? byId(String id) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    return idx == -1 ? null : _schedules[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _schedules = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getRecurringInvoices().listen(
      (schedules) {
        _schedules = schedules;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load billing schedules.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> add(RecurringInvoiceModel schedule) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.addRecurringInvoice(schedule);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to save the schedule.');
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> update(RecurringInvoiceModel schedule) => _guard(
    () => _databaseService.updateRecurringInvoice(schedule),
    'Failed to update the schedule.',
  );

  Future<bool> remove(String id) => _guard(
    () => _databaseService.deleteRecurringInvoice(id),
    'Failed to delete the schedule.',
  );

  Future<bool> setStatus(
    RecurringInvoiceModel schedule,
    RecurringInvoiceStatus status,
  ) => update(schedule.copyWith(status: status, updatedAt: DateTime.now()));

  /// Issues the invoice [schedule] owes. Returns its id, or null when the
  /// schedule was not due.
  Future<String?> generateOne({
    required RecurringInvoiceModel schedule,
    required String invoicePrefix,
    required String userId,
    required String userName,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _generate(
        schedule: schedule,
        invoicePrefix: invoicePrefix,
        userId: userId,
        userName: userName,
      );
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not generate that invoice.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Issues every invoice currently due.
  ///
  /// Sequential rather than concurrent on purpose: invoice numbers come from a
  /// shared counter, and racing several allocations against it is how two
  /// invoices end up with the same number.
  Future<RecurringRunResult> generateAllDue({
    required String invoicePrefix,
    required String userId,
    required String userName,
  }) async {
    if (_isBusy) {
      return const RecurringRunResult(
        generated: [],
        skipped: 0,
        failures: {},
      );
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    final generated = <String>[];
    final failures = <String, String>{};
    var skipped = 0;

    try {
      for (final schedule in due) {
        try {
          final id = await _generate(
            schedule: schedule,
            invoicePrefix: invoicePrefix,
            userId: userId,
            userName: userName,
          );
          if (id == null) {
            skipped++;
          } else {
            generated.add(id);
          }
        } catch (e) {
          failures[_labelOf(schedule)] = friendlyError(
            e,
            fallback: 'Generation failed.',
          );
        }
      }
    } finally {
      _isBusy = false;
      notifyListeners();
    }

    return RecurringRunResult(
      generated: generated,
      skipped: skipped,
      failures: failures,
    );
  }

  Future<String?> _generate({
    required RecurringInvoiceModel schedule,
    required String invoicePrefix,
    required String userId,
    required String userName,
  }) async {
    // Allocated before the transaction: the counter lives in its own document
    // and reading it inside would widen the transaction for no benefit. If the
    // transaction then finds the schedule already generated, the number is
    // simply not used — a gap in the sequence, which is the cheaper failure.
    final number = await _databaseService.getNextInvoiceNumber(invoicePrefix);
    return _databaseService.generateRecurringInvoice(
      schedule: schedule,
      invoiceNumber: number,
      userId: userId,
      userName: userName,
      build: (issueDate, invoiceNumber) =>
          buildInvoice(schedule, issueDate, invoiceNumber, userId, userName),
    );
  }

  /// The invoice [schedule] would produce on [issueDate].
  ///
  /// Public so the editor can preview the exact document the schedule will
  /// issue, rather than approximating it.
  static InvoiceModel buildInvoice(
    RecurringInvoiceModel schedule,
    DateTime issueDate,
    String invoiceNumber,
    String userId,
    String userName,
  ) {
    final totals = _totalsFor(schedule);
    final now = DateTime.now();
    return InvoiceModel(
      id: '',
      invoiceType: InvoiceType.sales,
      invoiceNumber: invoiceNumber,
      customerId: schedule.customerId,
      customerName: schedule.customerName,
      customerPhone: schedule.customerPhone,
      customerAddress: schedule.customerAddress,
      status: schedule.issueStatus,
      items: schedule.items,
      discountPercent: schedule.discountPercent,
      discountAmount: schedule.discountAmount,
      taxLabel: schedule.taxLabel,
      subtotal: totals.subtotal,
      totalDiscount: totals.totalDiscount,
      invoiceDiscount: totals.invoiceDiscount,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      amountDue: totals.grandTotal,
      invoiceDate: issueDate,
      dueDate: issueDate.add(Duration(days: schedule.paymentTermDays)),
      notes: schedule.notes,
      termsText: schedule.termsText,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
      updatedAt: now,
    );
  }

  static InvoiceTotals _totalsFor(RecurringInvoiceModel schedule) {
    return calculateInvoiceTotals(
      lines: schedule.items
          .map(
            (i) => InvoiceTotalsLineInput(
              quantity: i.quantity,
              unitPrice: i.unitPrice,
              lineDiscountPercent: i.discountPercent,
              lineTaxRate: i.taxRate,
            ),
          )
          .toList(),
      invoiceDiscountPercent: schedule.discountPercent,
      invoiceDiscountAmount: schedule.discountAmount,
      taxEnabled: schedule.items.any((i) => i.taxRate > 0),
      discountEnabled:
          schedule.discountPercent > 0 ||
          schedule.discountAmount > 0 ||
          schedule.items.any((i) => i.discountPercent > 0),
    );
  }

  /// What one run of [schedule] would bill.
  static double totalOf(RecurringInvoiceModel schedule) =>
      _totalsFor(schedule).grandTotal;

  double _totalOf(RecurringInvoiceModel schedule) => totalOf(schedule);

  static String _labelOf(RecurringInvoiceModel schedule) =>
      schedule.title.isNotEmpty
      ? schedule.title
      : (schedule.customerName.isNotEmpty
            ? schedule.customerName
            : 'Schedule ${schedule.id}');

  Future<bool> _guard(Future<void> Function() action, String fallback) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
