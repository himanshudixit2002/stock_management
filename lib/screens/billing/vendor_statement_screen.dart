import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../services/billing_pdf_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart'
    show showSearchablePicker, PickerItem;
import 'package:printing/printing.dart';

class VendorStatementScreen extends StatefulWidget {
  const VendorStatementScreen({super.key});

  @override
  State<VendorStatementScreen> createState() => _VendorStatementScreenState();
}

class _VendorStatementScreenState extends State<VendorStatementScreen> {
  String? _selectedVendorId;
  String _selectedVendorName = '';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isGenerating = false;

  static final _numFmt = NumberFormat('#,##0.00');

  List<InvoiceModel> _getFilteredInvoices(BillingProvider billing) {
    if (_selectedVendorId == null) return [];
    return billing
        .invoicesForVendor(_selectedVendorId!)
        .where(
          (i) =>
              !i.isCancelled &&
              !i.invoiceDate.isBefore(_startDate) &&
              !i.invoiceDate.isAfter(_endDate.add(const Duration(days: 1))),
        )
        .toList()
      ..sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));
  }

  Future<void> _generatePdf() async {
    if (_selectedVendorId == null) return;
    setState(() => _isGenerating = true);
    final billing = context.read<BillingProvider>();
    final bs = context.read<BillingSettingsProvider>().settings;
    final invoices = _getFilteredInvoices(billing);
    final pdfService = BillingPdfService();

    try {
      final result = await pdfService.generateVendorStatement(
        vendorName: _selectedVendorName,
        invoices: invoices,
        startDate: _startDate,
        endDate: _endDate,
        bs: bs,
      );
      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (_) async => Uint8List.fromList(result.bytes),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to generate PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final vendors = context.watch<VendorProvider>().activeVendors;
    final invoices = _getFilteredInvoices(billing);

    double totalBilled = 0, totalPaid = 0;
    for (final inv in invoices) {
      totalBilled += inv.grandTotal;
      totalPaid += inv.amountPaid;
    }
    final outstanding = totalBilled - totalPaid;

    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Statement')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.formMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              12,
              Responsive.horizontalPadding(context),
              80,
            ),
            children: [
              GlassPanel(
                borderRadius: 14,
                useContentVariant: true,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Vendor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final value = await showSearchablePicker(
                          context: context,
                          items: vendors
                              .map(
                                (v) => PickerItem(
                                  value: v.id,
                                  label: v.name,
                                  subtitle: v.phone,
                                ),
                              )
                              .toList(),
                          selectedValue: _selectedVendorId,
                          title: 'Select Vendor',
                        );
                        if (value != null) {
                          final v = vendors.firstWhere((v) => v.id == value);
                          setState(() {
                            _selectedVendorId = v.id;
                            _selectedVendorName = v.name;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.dividerC(context)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedVendorName.isEmpty
                                    ? 'Choose vendor'
                                    : _selectedVendorName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _selectedVendorName.isEmpty
                                      ? AppTheme.textMuted
                                      : AppTheme.textPri(context),
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                borderRadius: 14,
                useContentVariant: true,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: 'From',
                        date: _startDate,
                        onPicked: (d) => setState(() => _startDate = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTile(
                        label: 'To',
                        date: _endDate,
                        onPicked: (d) => setState(() => _endDate = d),
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedVendorId != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MiniStat(
                      label: 'Billed',
                      value: '$sym${_numFmt.format(totalBilled)}',
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    _MiniStat(
                      label: 'Paid',
                      value: '$sym${_numFmt.format(totalPaid)}',
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    _MiniStat(
                      label: 'Outstanding',
                      value: '$sym${_numFmt.format(outstanding)}',
                      color: AppTheme.dangerColor,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (invoices.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No bills in this period',
                        style: TextStyle(color: AppTheme.textTer(context)),
                      ),
                    ),
                  )
                else
                  ...invoices.map((inv) => _BillRow(invoice: inv, sym: sym)),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: _selectedVendorId != null && invoices.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isGenerating ? null : _generatePdf,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Generate PDF'),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPicked;
  const _DateTile({
    required this.label,
    required this.date,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.dividerC(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: AppTheme.textTer(context),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTer(context),
                  ),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(date),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassPanel(
        borderRadius: 10,
        useContentVariant: true,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: AppTheme.textTer(context)),
            ),
            const SizedBox(height: 2),
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

class _BillRow extends StatelessWidget {
  final InvoiceModel invoice;
  final String sym;
  const _BillRow({required this.invoice, required this.sym});

  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _numFmt = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        borderRadius: 12,
        useContentVariant: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.invoiceDetail,
              arguments: invoice.id,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${_dateFmt.format(invoice.invoiceDate)} · ${invoice.statusLabel}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$sym${_numFmt.format(invoice.grandTotal)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        invoice.amountDue > 0
                            ? 'Due: $sym${_numFmt.format(invoice.amountDue)}'
                            : 'Paid',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: invoice.amountDue > 0
                              ? AppTheme.dangerColor
                              : AppTheme.successColor,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppTheme.textTer(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
