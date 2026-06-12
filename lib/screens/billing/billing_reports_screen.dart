import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/chart_empty_state.dart';
import '../../widgets/animations.dart';

class BillingReportsScreen extends StatefulWidget {
  const BillingReportsScreen({super.key});

  @override
  State<BillingReportsScreen> createState() => _BillingReportsScreenState();
}

class _BillingReportsScreenState extends State<BillingReportsScreen> {
  InvoiceType? _typeFilter;
  static final _numFmt = NumberFormat('#,##0.00');

  List<InvoiceModel> _filterByType(List<InvoiceModel> invoices) {
    var result = invoices.where((i) => !i.isCancelled).toList();
    if (_typeFilter != null) {
      result = result.where((i) => i.invoiceType == _typeFilter).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final invoices = _filterByType(billing.invoices);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_rounded),
            tooltip: 'Customer Statement',
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.customerStatement),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              12,
              Responsive.horizontalPadding(context),
              40,
            ),
            children: [
              _buildTypeToggle(context),
              const SizedBox(height: 12),
              FadeSlideIn(
                index: 0,
                child: _buildRevenueSection(
                  context,
                  billing,
                  sym,
                  startOfDay,
                  startOfWeek,
                  startOfMonth,
                ),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                index: 1,
                child: _buildAgingReport(context, invoices, sym),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                index: 2,
                child: _buildPaymentMethodBreakdown(context, invoices, sym),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                index: 3,
                child: _buildTaxCollected(context, invoices, bs, sym),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                index: 4,
                child: _buildTopParties(context, invoices, sym),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle(BuildContext context) {
    Widget chip(String label, InvoiceType? type) {
      final selected = _typeFilter == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _typeFilter = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.primaryColor.withValues(alpha: 0.06),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textSec(context),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('All', null),
        const SizedBox(width: 6),
        chip('Sales', InvoiceType.sales),
        const SizedBox(width: 6),
        chip('Purchase', InvoiceType.purchase),
      ],
    );
  }

  Widget _sectionHeader(String title, Color color, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.iconMute(context),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueSection(
    BuildContext context,
    BillingProvider billing,
    String sym,
    DateTime startOfDay,
    DateTime startOfWeek,
    DateTime startOfMonth,
  ) {
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final endOfMonth = DateTime(startOfMonth.year, startOfMonth.month + 1, 1);

    double periodRevenue(DateTime start, DateTime end) {
      return _filterByType(billing.invoices)
          .where(
            (i) =>
                i.invoiceDate.isAfter(
                  start.subtract(const Duration(seconds: 1)),
                ) &&
                i.invoiceDate.isBefore(end.add(const Duration(days: 1))),
          )
          .fold(0.0, (s, i) => s + i.grandTotal);
    }

    final filtered = _filterByType(billing.invoices);
    final totalInvoiced = filtered.fold(0.0, (s, i) => s + i.grandTotal);
    final totalOutstanding = filtered.fold(
      0.0,
      (double s, InvoiceModel i) => s + i.amountDue,
    );
    final overdueCount = filtered
        .where((i) => i.isOverdue || (i.overdueDays > 0 && !i.isPaid))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Revenue Summary', AppTheme.primaryColor, context),
        Row(
          children: [
            _RevenueCard(
              label: 'Today',
              value:
                  '$sym${_numFmt.format(periodRevenue(startOfDay, endOfDay))}',
              color: AppTheme.successColor,
            ),
            const SizedBox(width: 8),
            _RevenueCard(
              label: 'This Week',
              value:
                  '$sym${_numFmt.format(periodRevenue(startOfWeek, endOfWeek))}',
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 8),
            _RevenueCard(
              label: 'This Month',
              value:
                  '$sym${_numFmt.format(periodRevenue(startOfMonth, endOfMonth))}',
              color: AppTheme.indigoColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _RevenueCard(
              label: 'Total Invoiced',
              value: '$sym${_numFmt.format(totalInvoiced)}',
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 8),
            _RevenueCard(
              label: 'Outstanding',
              value: '$sym${_numFmt.format(totalOutstanding)}',
              color: AppTheme.dangerColor,
            ),
            const SizedBox(width: 8),
            _RevenueCard(
              label: 'Overdue',
              value: '$overdueCount invoices',
              color: AppTheme.warningColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAgingReport(
    BuildContext context,
    List<InvoiceModel> invoices,
    String sym,
  ) {
    final unpaid = invoices.where((i) => !i.isPaid && i.amountDue > 0).toList();
    final now = DateTime.now();
    double b0_30 = 0, b31_60 = 0, b61_90 = 0, b90plus = 0;
    for (final inv in unpaid) {
      final days = now.difference(inv.dueDate).inDays;
      if (days <= 0) {
        b0_30 += inv.amountDue;
      } else if (days <= 30) {
        b0_30 += inv.amountDue;
      } else if (days <= 60) {
        b31_60 += inv.amountDue;
      } else if (days <= 90) {
        b61_90 += inv.amountDue;
      } else {
        b90plus += inv.amountDue;
      }
    }
    final total = b0_30 + b31_60 + b61_90 + b90plus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Aging Report', AppTheme.warningColor, context),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _agingRow(
                'Current / 0-30 days',
                b0_30,
                total,
                sym,
                AppTheme.successColor,
                context,
              ),
              _agingRow(
                '31-60 days',
                b31_60,
                total,
                sym,
                AppTheme.warningColor,
                context,
              ),
              _agingRow(
                '61-90 days',
                b61_90,
                total,
                sym,
                AppTheme.accentColor,
                context,
              ),
              _agingRow(
                '90+ days',
                b90plus,
                total,
                sym,
                AppTheme.dangerColor,
                context,
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Outstanding',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    '$sym${_numFmt.format(total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agingRow(
    String label,
    double amount,
    double total,
    String sym,
    Color color,
    BuildContext context,
  ) {
    final pct = total > 0 ? amount / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$sym${_numFmt.format(amount)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppTheme.dividerC(context),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown(
    BuildContext context,
    List<InvoiceModel> invoices,
    String sym,
  ) {
    final methodTotals = <String, double>{};
    for (final inv in invoices) {
      for (final p in inv.payments) {
        methodTotals[p.method] = (methodTotals[p.method] ?? 0) + p.amount;
      }
    }
    final sorted = methodTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (s, e) => s + e.value);
    final methodLabels = {
      'cash': 'Cash',
      'upi': 'UPI',
      'card': 'Card',
      'bank': 'Bank Transfer',
      'cheque': 'Cheque',
    };
    final methodColors = {
      'cash': AppTheme.successColor,
      'upi': AppTheme.primaryColor,
      'card': AppTheme.indigoColor,
      'bank': AppTheme.warningColor,
      'cheque': AppTheme.accentColor,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Payment Methods', AppTheme.indigoColor, context),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.all(14),
          child: sorted.isEmpty
              ? const ChartEmptyState(
                  message: 'No payments yet',
                  icon: Icons.payments_rounded,
                )
              : Column(
                  children: sorted.map((e) {
                    final color = methodColors[e.key] ?? AppTheme.primaryColor;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              methodLabels[e.key] ?? e.key,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '$sym${_numFmt.format(e.value)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 40,
                            child: Text(
                              total > 0
                                  ? '${(e.value / total * 100).toStringAsFixed(0)}%'
                                  : '',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textTer(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildTaxCollected(
    BuildContext context,
    List<InvoiceModel> invoices,
    dynamic bs,
    String sym,
  ) {
    final taxByRate = <double, double>{};
    for (final inv in invoices) {
      for (final item in inv.items) {
        if (item.taxRate > 0) {
          taxByRate[item.taxRate] =
              (taxByRate[item.taxRate] ?? 0) + item.lineTax;
        }
      }
    }
    final sorted = taxByRate.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalTax = sorted.fold(0.0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Tax Collected', AppTheme.warningColor, context),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.all(14),
          child: sorted.isEmpty
              ? const ChartEmptyState(
                  message: 'No tax collected',
                  icon: Icons.receipt_long_rounded,
                )
              : Column(
                  children: [
                    ...sorted.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${bs.taxLabel} @ ${e.key}%',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              '$sym${_numFmt.format(e.value)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Tax',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '$sym${_numFmt.format(totalTax)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTopParties(
    BuildContext context,
    List<InvoiceModel> invoices,
    String sym,
  ) {
    final partyTotals = <String, double>{};
    final partyNames = <String, String>{};
    for (final inv in invoices) {
      final pid = inv.isSales ? inv.customerId : inv.vendorId;
      final pname = inv.isSales ? inv.customerName : inv.vendorName;
      if (pid.isEmpty) continue;
      partyTotals[pid] = (partyTotals[pid] ?? 0) + inv.grandTotal;
      partyNames[pid] = pname;
    }
    final sorted = partyTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();

    final sectionTitle = _typeFilter == InvoiceType.purchase
        ? 'Spend by Vendor'
        : _typeFilter == InvoiceType.sales
        ? 'Revenue by Customer'
        : 'Revenue by Party';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(sectionTitle, AppTheme.successColor, context),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.all(14),
          child: top.isEmpty
              ? const ChartEmptyState(
                  message: 'No data',
                  icon: Icons.people_alt_rounded,
                )
              : Column(
                  children: top.asMap().entries.map((e) {
                    final idx = e.key;
                    final entry = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${idx + 1}.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTer(context),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              partyNames[entry.key] ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '$sym${_numFmt.format(entry.value)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RevenueCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassPanel(
        borderRadius: 12,
        useContentVariant: true,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textTer(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
