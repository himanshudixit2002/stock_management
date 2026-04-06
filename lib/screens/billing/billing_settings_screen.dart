import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/billing_settings_model.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';

class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key});

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen> {
  late TextEditingController _businessNameCtrl;
  late TextEditingController _businessAddressCtrl;
  late TextEditingController _businessPhoneCtrl;
  late TextEditingController _businessEmailCtrl;
  late TextEditingController _taxIdCtrl;
  late TextEditingController _taxLabelCtrl;
  late TextEditingController _taxRateCtrl;
  late TextEditingController _prefixCtrl;
  late TextEditingController _nextNumCtrl;
  late TextEditingController _purchasePrefixCtrl;
  late TextEditingController _nextPurchaseNumCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _currencyCtrl;
  late TextEditingController _defaultNotesCtrl;
  late bool _taxInclusive;
  late int _paymentTermDays;
  late bool _enableTax;
  late bool _enableDiscounts;
  late bool _enablePaymentTracking;
  late bool _autoCreateSoForStandaloneSales;
  late bool _autoCreatePoForStandaloneBills;
  bool _isSaving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _businessNameCtrl = TextEditingController();
    _businessAddressCtrl = TextEditingController();
    _businessPhoneCtrl = TextEditingController();
    _businessEmailCtrl = TextEditingController();
    _taxIdCtrl = TextEditingController();
    _taxLabelCtrl = TextEditingController();
    _taxRateCtrl = TextEditingController();
    _prefixCtrl = TextEditingController();
    _nextNumCtrl = TextEditingController();
    _purchasePrefixCtrl = TextEditingController();
    _nextPurchaseNumCtrl = TextEditingController();
    _footerCtrl = TextEditingController();
    _currencyCtrl = TextEditingController();
    _defaultNotesCtrl = TextEditingController();
    _taxInclusive = false;
    _paymentTermDays = 0;
    _enableTax = true;
    _enableDiscounts = true;
    _enablePaymentTracking = true;
    _autoCreateSoForStandaloneSales = true;
    _autoCreatePoForStandaloneBills = true;

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  void _loadSettings() {
    final bs = context.read<BillingSettingsProvider>().settings;
    _businessNameCtrl.text = bs.businessName;
    _businessAddressCtrl.text = bs.businessAddress;
    _businessPhoneCtrl.text = bs.businessPhone;
    _businessEmailCtrl.text = bs.businessEmail;
    _taxIdCtrl.text = bs.taxId;
    _taxLabelCtrl.text = bs.taxLabel;
    _taxRateCtrl.text = bs.defaultTaxRate > 0
        ? bs.defaultTaxRate.toString()
        : '';
    _prefixCtrl.text = bs.invoicePrefix;
    _nextNumCtrl.text = bs.nextInvoiceNumber.toString();
    _purchasePrefixCtrl.text = bs.purchasePrefix;
    _nextPurchaseNumCtrl.text = bs.nextPurchaseNumber.toString();
    _footerCtrl.text = bs.invoiceFooter;
    _currencyCtrl.text = bs.currencySymbol;
    _defaultNotesCtrl.text = bs.defaultNotes;
    _taxInclusive = bs.taxInclusive;
    _paymentTermDays = bs.defaultPaymentTermDays;
    _enableTax = bs.enableTax;
    _enableDiscounts = bs.enableDiscounts;
    _enablePaymentTracking = bs.enablePaymentTracking;
    _autoCreateSoForStandaloneSales = bs.autoCreateSalesOrderForStandaloneSales;
    _autoCreatePoForStandaloneBills =
        bs.autoCreatePurchaseOrderForStandaloneBills;
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final updated = BillingSettings(
      billingEnabled: context
          .read<BillingSettingsProvider>()
          .settings
          .billingEnabled,
      businessName: _businessNameCtrl.text.trim(),
      businessAddress: _businessAddressCtrl.text.trim(),
      businessPhone: _businessPhoneCtrl.text.trim(),
      businessEmail: _businessEmailCtrl.text.trim(),
      taxId: _taxIdCtrl.text.trim(),
      taxLabel: _taxLabelCtrl.text.trim().isEmpty
          ? 'GST'
          : _taxLabelCtrl.text.trim(),
      defaultTaxRate: double.tryParse(_taxRateCtrl.text) ?? 0,
      taxInclusive: _taxInclusive,
      invoicePrefix: _prefixCtrl.text.trim().isEmpty
          ? 'INV'
          : _prefixCtrl.text.trim(),
      nextInvoiceNumber: int.tryParse(_nextNumCtrl.text) ?? 1,
      defaultPaymentTermDays: _paymentTermDays,
      invoiceFooter: _footerCtrl.text.trim(),
      currencySymbol: _currencyCtrl.text.trim().isEmpty
          ? '₹'
          : _currencyCtrl.text.trim(),
      enableTax: _enableTax,
      enableDiscounts: _enableDiscounts,
      enablePaymentTracking: _enablePaymentTracking,
      purchasePrefix: _purchasePrefixCtrl.text.trim().isEmpty
          ? 'BILL'
          : _purchasePrefixCtrl.text.trim(),
      nextPurchaseNumber: int.tryParse(_nextPurchaseNumCtrl.text) ?? 1,
      defaultNotes: _defaultNotesCtrl.text.trim(),
      autoCreateSalesOrderForStandaloneSales: _autoCreateSoForStandaloneSales,
      autoCreatePurchaseOrderForStandaloneBills: _autoCreatePoForStandaloneBills,
    );
    final ok = await context.read<BillingSettingsProvider>().updateSettings(
      updated,
    );
    setState(() => _isSaving = false);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Billing settings saved'),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessEmailCtrl.dispose();
    _taxIdCtrl.dispose();
    _taxLabelCtrl.dispose();
    _taxRateCtrl.dispose();
    _prefixCtrl.dispose();
    _nextNumCtrl.dispose();
    _purchasePrefixCtrl.dispose();
    _nextPurchaseNumCtrl.dispose();
    _footerCtrl.dispose();
    _currencyCtrl.dispose();
    _defaultNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Billing Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.formMaxWidth(context),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    12,
                    Responsive.horizontalPadding(context),
                    24,
                  ),
                  children: [
                    _section('Company Profile', AppTheme.primaryColor, [
                      _field(
                        _businessNameCtrl,
                        'Business Name',
                        Icons.business_rounded,
                      ),
                      _field(
                        _businessAddressCtrl,
                        'Address',
                        Icons.location_on_rounded,
                        maxLines: 2,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _businessPhoneCtrl,
                              'Phone',
                              Icons.phone_rounded,
                              keyboard: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _businessEmailCtrl,
                              'Email',
                              Icons.email_rounded,
                              keyboard: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      _field(_taxIdCtrl, 'Tax ID / GSTIN', Icons.badge_rounded),
                    ]),
                    const SizedBox(height: 16),
                    _section('Tax Configuration', AppTheme.warningColor, [
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _taxLabelCtrl,
                              'Tax Label (e.g. GST)',
                              Icons.label_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _taxRateCtrl,
                              'Default Tax %',
                              Icons.percent_rounded,
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Tax Inclusive',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Prices include tax',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _taxInclusive,
                        onChanged: (v) => setState(() => _taxInclusive = v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Invoice Numbering', AppTheme.indigoColor, [
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _prefixCtrl,
                              'Prefix (e.g. INV)',
                              Icons.tag_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _nextNumCtrl,
                              'Next Number',
                              Icons.numbers_rounded,
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _currencyCtrl,
                              'Currency Symbol',
                              Icons.currency_rupee_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _paymentTermDays,
                              decoration: InputDecoration(
                                labelText: 'Default Terms',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              items: [0, 15, 30, 60, 90]
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d == 0 ? 'Due on Receipt' : 'Net $d',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _paymentTermDays = v ?? 0),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Purchase Bill Numbering', AppTheme.warningColor, [
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _purchasePrefixCtrl,
                              'Purchase Prefix (e.g. BILL)',
                              Icons.tag_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _nextPurchaseNumCtrl,
                              'Next Purchase Number',
                              Icons.numbers_rounded,
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Defaults', AppTheme.infoColor, [
                      _field(
                        _defaultNotesCtrl,
                        'Default Notes (auto-filled on new invoices)',
                        Icons.sticky_note_2_rounded,
                        maxLines: 3,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Invoice Footer', AppTheme.accentColor, [
                      _field(
                        _footerCtrl,
                        'Terms / Footer Text',
                        Icons.notes_rounded,
                        maxLines: 3,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Features', AppTheme.successColor, [
                      SwitchListTile(
                        title: const Text(
                          'Enable Tax',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Show tax fields on invoices',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _enableTax,
                        onChanged: (v) => setState(() => _enableTax = v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Enable Discounts',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Allow discounts on invoices',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _enableDiscounts,
                        onChanged: (v) => setState(() => _enableDiscounts = v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Payment Tracking',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Track payments against invoices',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _enablePaymentTracking,
                        onChanged: (v) =>
                            setState(() => _enablePaymentTracking = v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Auto sales order for standalone invoices',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'When saving a non-draft sales invoice without a linked order, create a dispatched order for traceability',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _autoCreateSoForStandaloneSales,
                        onChanged: (v) => setState(
                          () => _autoCreateSoForStandaloneSales = v,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Auto purchase order for standalone bills',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'When saving a non-draft purchase bill without a linked order, create a received order for traceability',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _autoCreatePoForStandaloneBills,
                        onChanged: (v) => setState(
                          () => _autoCreatePoForStandaloneBills = v,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, Color color, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
        ),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          padding: const EdgeInsets.all(14),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        keyboardType: keyboard,
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        10,
        Responsive.horizontalPadding(context),
        10,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(top: BorderSide(color: AppTheme.dividerC(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Settings',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
          ),
        ),
      ),
    );
  }
}
