import '../models/commission_plan_model.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';

/// One invoice's contribution to somebody's commission.
class CommissionLine {
  const CommissionLine({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.date,
    required this.customerName,
    required this.invoiceTotal,
    required this.base,
    required this.commission,
    required this.planName,
    required this.collectedShare,
  });

  final String invoiceId;
  final String invoiceNumber;
  final DateTime date;
  final String customerName;

  /// Face value of the invoice, for context next to the base.
  final double invoiceTotal;

  /// What the rate was applied to — revenue or margin, after the collected
  /// share is taken into account.
  final double base;

  final double commission;
  final String planName;

  /// 0..1 share of the invoice actually paid. 1 on plans that pay on issue.
  final double collectedShare;
}

/// What one person earned over the period.
class CommissionStatement {
  const CommissionStatement({
    required this.userId,
    required this.userName,
    required this.planName,
    required this.basis,
    required this.lines,
    required this.baseTotal,
    required this.commissionTotal,
    required this.salesTotal,
  });

  final String userId;
  final String userName;
  final String planName;
  final CommissionBasis basis;

  /// Newest first.
  final List<CommissionLine> lines;

  final double baseTotal;
  final double commissionTotal;

  /// Face value of the invoices behind it.
  final double salesTotal;

  int get invoiceCount => lines.length;

  /// Commission as a share of the sales it came from, which is the number
  /// people actually argue about.
  double get effectiveRate {
    if (salesTotal <= 0) return 0;
    return (commissionTotal / salesTotal) * 100;
  }
}

/// A period's commission, for everybody.
class CommissionRun {
  const CommissionRun({
    required this.from,
    required this.to,
    required this.statements,
    required this.totalCommission,
    required this.totalBase,
    required this.invoicesConsidered,
    required this.invoicesWithoutPlan,
    required this.invoicesBelowMinimum,
  });

  final DateTime from;

  /// Exclusive.
  final DateTime to;

  /// Highest earner first.
  final List<CommissionStatement> statements;

  final double totalCommission;
  final double totalBase;
  final int invoicesConsidered;

  /// Sales by somebody no active plan covers. Surfaced rather than swallowed:
  /// it is nearly always a plan that forgot to name a new starter.
  final int invoicesWithoutPlan;

  final int invoicesBelowMinimum;

  static final CommissionRun empty = CommissionRun(
    from: DateTime.fromMillisecondsSinceEpoch(0),
    to: DateTime.fromMillisecondsSinceEpoch(0),
    statements: const [],
    totalCommission: 0,
    totalBase: 0,
    invoicesConsidered: 0,
    invoicesWithoutPlan: 0,
    invoicesBelowMinimum: 0,
  );
}

/// Works out what each salesperson earned, from invoices and commission plans.
///
/// Pure and synchronous, and unit-tested, because a commission figure that
/// nobody can reproduce is a figure nobody will trust.
class CommissionCalculator {
  CommissionCalculator._();

  /// The plan that applies to [userId] on [date].
  ///
  /// A plan naming the user beats a plan naming everybody, so a scheme for one
  /// star seller can sit alongside the house default without either needing to
  /// know about the other. Among equally specific plans the most recently
  /// updated wins, which is what "we changed the scheme" means in practice.
  static CommissionPlanModel? planFor({
    required List<CommissionPlanModel> plans,
    required String userId,
    required DateTime date,
  }) {
    CommissionPlanModel? best;
    var bestSpecific = false;
    for (final plan in plans) {
      if (!plan.isActive) continue;
      if (!plan.coversDate(date)) continue;
      if (!plan.appliesTo(userId)) continue;
      final specific = plan.userIds.contains(userId);
      if (best == null ||
          (specific && !bestSpecific) ||
          (specific == bestSpecific &&
              plan.updatedAt.isAfter(best.updatedAt))) {
        best = plan;
        bestSpecific = specific;
      }
    }
    return best;
  }

  /// The share of an invoice that has actually been collected, 0..1.
  static double collectedShare(InvoiceModel invoice) {
    if (invoice.grandTotal <= 0) return 0;
    final share = invoice.amountPaid / invoice.grandTotal;
    if (share <= 0) return 0;
    return share > 1 ? 1 : share;
  }

  /// Revenue or margin on one invoice, before any collected-share weighting.
  ///
  /// Revenue is net of line discounts and excludes tax — commission on the
  /// government's money would be an odd scheme. Margin subtracts the product's
  /// cost price; a product that no longer exists contributes its full revenue,
  /// because guessing a cost would understate the seller's earnings on the
  /// strength of a deleted record.
  static double baseFor({
    required InvoiceModel invoice,
    required CommissionBasis basis,
    required Map<String, ProductModel> productsById,
  }) {
    var base = 0.0;
    for (final item in invoice.items) {
      final gross = item.quantity * item.unitPrice;
      final net = gross - (gross * (item.discountPercent / 100));
      if (basis == CommissionBasis.revenue) {
        base += net;
      } else {
        final cost = productsById[item.productId]?.costPrice ?? 0;
        base += net - (cost * item.quantity);
      }
    }
    // A whole-invoice discount is applied to every line proportionally, so a
    // 10% off at the bottom of the invoice is not commission-free.
    if (invoice.invoiceDiscount > 0 && invoice.subtotal > 0) {
      final factor = 1 - (invoice.invoiceDiscount / invoice.subtotal);
      base *= factor < 0 ? 0 : factor;
    }
    return base;
  }

  /// The rate for an invoice: a single line uses its category's rate, a mixed
  /// invoice uses the units-weighted mean of them, so a basket of two
  /// categories does not silently take whichever product happened to be first.
  static double rateFor({
    required InvoiceModel invoice,
    required CommissionPlanModel plan,
    required Map<String, ProductModel> productsById,
  }) {
    if (plan.categoryRates.isEmpty) return plan.defaultPercent;
    var weighted = 0.0;
    var weight = 0.0;
    for (final item in invoice.items) {
      final categoryId = productsById[item.productId]?.categoryId ?? '';
      final gross = item.quantity * item.unitPrice;
      if (gross <= 0) continue;
      weighted += plan.percentFor(categoryId) * gross;
      weight += gross;
    }
    if (weight <= 0) return plan.defaultPercent;
    return weighted / weight;
  }

  static CommissionRun run({
    required List<InvoiceModel> invoices,
    required List<CommissionPlanModel> plans,
    required List<ProductModel> products,
    required DateTime from,
    required DateTime to,
    Map<String, String> userNames = const {},
  }) {
    final productsById = {for (final p in products) p.id: p};

    final byUser = <String, List<CommissionLine>>{};
    final userPlan = <String, CommissionPlanModel>{};
    final userSales = <String, double>{};
    // Names taken off the invoices themselves, so a statement is attributable
    // even when the caller passes no directory of users.
    final userDisplay = <String, String>{};

    var considered = 0;
    var withoutPlan = 0;
    var belowMinimum = 0;

    for (final invoice in invoices) {
      if (!invoice.isSales) continue;
      if (invoice.isCancelled || invoice.isDraft) continue;
      final date = invoice.invoiceDate;
      if (date.isBefore(from) || !date.isBefore(to)) continue;
      considered++;

      final userId = invoice.createdBy;
      if (userId.isEmpty) {
        withoutPlan++;
        continue;
      }

      final plan = planFor(plans: plans, userId: userId, date: date);
      if (plan == null) {
        withoutPlan++;
        continue;
      }
      if (invoice.grandTotal < plan.minimumSaleValue) {
        belowMinimum++;
        continue;
      }

      final share = plan.includeUnpaid ? 1.0 : collectedShare(invoice);
      if (share <= 0) continue;

      final rawBase = baseFor(
        invoice: invoice,
        basis: plan.basis,
        productsById: productsById,
      );
      // A negative margin earns nothing rather than clawing back: a loss-making
      // sale is a pricing problem, and netting it off another sale's commission
      // is a payroll argument nobody wins.
      final base = (rawBase <= 0 ? 0.0 : rawBase) * share;
      final percent = rateFor(
        invoice: invoice,
        plan: plan,
        productsById: productsById,
      );
      final commission = base * (percent / 100);

      byUser.putIfAbsent(userId, () => []).add(
        CommissionLine(
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
          date: date,
          customerName: invoice.customerName,
          invoiceTotal: invoice.grandTotal,
          base: base,
          commission: commission,
          planName: plan.name,
          collectedShare: share,
        ),
      );
      userPlan[userId] = plan;
      if (invoice.createdByName.isNotEmpty) {
        userDisplay[userId] = invoice.createdByName;
      }
      userSales[userId] = (userSales[userId] ?? 0) + invoice.grandTotal;
    }

    final statements = <CommissionStatement>[];
    var totalCommission = 0.0;
    var totalBase = 0.0;

    for (final entry in byUser.entries) {
      final lines = entry.value
        ..sort((a, b) => b.date.compareTo(a.date));
      final plan = userPlan[entry.key]!;
      final baseTotal = lines.fold(0.0, (acc, l) => acc + l.base);
      final commissionTotal = lines.fold(0.0, (acc, l) => acc + l.commission);
      totalBase += baseTotal;
      totalCommission += commissionTotal;
      statements.add(
        CommissionStatement(
          userId: entry.key,
          userName:
              userNames[entry.key] ?? userDisplay[entry.key] ?? entry.key,
          planName: plan.name,
          basis: plan.basis,
          lines: lines,
          baseTotal: baseTotal,
          commissionTotal: commissionTotal,
          salesTotal: userSales[entry.key] ?? 0,
        ),
      );
    }

    statements.sort((a, b) => b.commissionTotal.compareTo(a.commissionTotal));

    return CommissionRun(
      from: from,
      to: to,
      statements: statements,
      totalCommission: totalCommission,
      totalBase: totalBase,
      invoicesConsidered: considered,
      invoicesWithoutPlan: withoutPlan,
      invoicesBelowMinimum: belowMinimum,
    );
  }
}
