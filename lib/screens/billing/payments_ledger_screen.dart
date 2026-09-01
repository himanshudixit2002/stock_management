import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../utils/currency.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';

/// One payment, lifted out of the invoice it is embedded in.
class _LedgerEntry {
  final PaymentRecord payment;
  final InvoiceModel invoice;

  const _LedgerEntry({required this.payment, required this.invoice});
}

/// Every payment across every invoice, in one place.
///
/// Payments are stored as an array on each invoice, so before this there was
/// no way to see what came in during a period, or to find a mistyped one
/// without opening invoices individually.
class PaymentsLedgerScreen extends StatefulWidget {
  const PaymentsLedgerScreen({super.key});

  @override
  State<PaymentsLedgerScreen> createState() => _PaymentsLedgerScreenState();
}

class _PaymentsLedgerScreenState extends State<PaymentsLedgerScreen> {
  /// null = both; true = received (sales); false = paid out (purchases).
  bool? _salesOnly;
  String _method = '';
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final invoices = context.watch<BillingProvider>().invoices;

    final entries = <_LedgerEntry>[];
    for (final inv in invoices) {
      if (inv.isCancelled) continue;
      for (final p in inv.payments) {
        entries.add(_LedgerEntry(payment: p, invoice: inv));
      }
    }
    entries.sort((a, b) => b.payment.date.compareTo(a.payment.date));

    final methods = <String>{for (final e in entries) e.payment.method}
      ..removeWhere((m) => m.isEmpty);

    final filtered = entries.where((e) {
      if (_salesOnly != null && e.invoice.isSales != _salesOnly) return false;
      if (_method.isNotEmpty && e.payment.method != _method) return false;
      if (_range != null) {
        final d = e.payment.date;
        if (d.isBefore(_range!.start)) return false;
        // End of the selected end-day, not its midnight.
        if (!d.isBefore(_range!.end.add(const Duration(days: 1)))) return false;
      }
      return true;
    }).toList();

    final received = filtered
        .where((e) => e.invoice.isSales)
        .fold<double>(0, (s, e) => s + e.payment.amount);
    final paidOut = filtered
        .where((e) => !e.invoice.isSales)
        .fold<double>(0, (s, e) => s + e.payment.amount);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.payments_rounded,
          color: AppTheme.successColor,
          title: 'Payments',
        ),
        actions: [
          IconButton(
            tooltip: 'Date range',
            icon: const Icon(Icons.date_range_rounded),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          if (_range != null)
            IconButton(
              tooltip: 'Clear range',
              icon: const Icon(Icons.clear_rounded),
              onPressed: () => setState(() => _range = null),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GlassPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Total(
                          label: 'Received',
                          value: received,
                          color: AppTheme.successColor,
                        ),
                      ),
                      Expanded(
                        child: _Total(
                          label: 'Paid out',
                          value: paidOut,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _Chip(
                    label: 'All',
                    selected: _salesOnly == null,
                    onTap: () => setState(() => _salesOnly = null),
                  ),
                  _Chip(
                    label: 'Received',
                    selected: _salesOnly == true,
                    onTap: () => setState(() => _salesOnly = true),
                  ),
                  _Chip(
                    label: 'Paid out',
                    selected: _salesOnly == false,
                    onTap: () => setState(() => _salesOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ...methods.map(
                    (m) => _Chip(
                      label: m,
                      selected: _method == m,
                      onTap: () => setState(
                        () => _method = _method == m ? '' : m,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.payments_rounded,
                      title: 'No payments',
                      subtitle:
                          'Nothing matches the current filters. Payments '
                          'appear here as soon as they are recorded.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) =>
                          _PaymentTile(entry: filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          Money.of(context, value),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.entry});

  final _LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final inbound = entry.invoice.isSales;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: ListTile(
          leading: Icon(
            inbound
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            color: inbound ? AppTheme.successColor : AppTheme.warningColor,
          ),
          title: Text(
            entry.invoice.partyName.isNotEmpty
                ? entry.invoice.partyName
                : entry.invoice.invoiceNumber,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              entry.invoice.invoiceNumber,
              AppDates.day.format(entry.payment.date),
              entry.payment.methodLabel,
              if (entry.payment.referenceNumber.isNotEmpty)
                'Ref ${entry.payment.referenceNumber}',
            ].join(' • '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Text(
            Money.of(context, entry.payment.amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: inbound ? AppTheme.successColor : AppTheme.warningColor,
            ),
          ),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.invoiceDetail,
            arguments: entry.invoice,
          ),
        ),
      ),
    );
  }
}
