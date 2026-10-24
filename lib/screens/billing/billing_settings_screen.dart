import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/billing_settings_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../settings/settings_focus.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animations.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/currency.dart';

class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key, this.focusId});

  /// Section to scroll to and flash, when arrived at from settings search.
  /// Currency, tax and invoice numbering are all found here, so this is the
  /// page settings search deep-links into most.
  final String? focusId;

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen>
    with SettingsFocusMixin {
  bool _resolvedFocus = false;

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
      currencySymbol: Money.symbolOrFallback(_currencyCtrl.text),
      enableTax: _enableTax,
      enableDiscounts: _enableDiscounts,
      enablePaymentTracking: _enablePaymentTracking,
      purchasePrefix: _purchasePrefixCtrl.text.trim().isEmpty
          ? 'BILL'
          : _purchasePrefixCtrl.text.trim(),
      nextPurchaseNumber: int.tryParse(_nextPurchaseNumCtrl.text) ?? 1,
      defaultNotes: _defaultNotesCtrl.text.trim(),
      autoCreateSalesOrderForStandaloneSales: _autoCreateSoForStandaloneSales,
      autoCreatePurchaseOrderForStandaloneBills:
          _autoCreatePoForStandaloneBills,
    );
    final ok = await context.read<BillingSettingsProvider>().updateSettings(
      updated,
    );
    // The guard has to come first: this setState ran before the `mounted`
    // check below, so leaving the screen while the save was in flight threw.
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      await showSuccessOverlay(context, message: 'Billing settings saved');
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
    if (!_resolvedFocus) {
      _resolvedFocus = true;
      focusAfterLayout(widget.focusId ?? settingsAnchorOf(context));
    }
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.receipt_long_rounded,
            color: AppTheme.successColor,
            title: 'Billing Settings',
          ),
        ),
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
                24,
              ),
              children: const [ShimmerLoading(layout: ShimmerLayout.detail)],
            ),
          ),
        ),
      );
    }

    final canEdit = _canEdit(context);

    return Scaffold(
      appBar: AppBar(
        // Was a bare text title, the one settings destination that did not
        // carry the app's icon+colour app bar. It is the page search deep-links
        // into most (currency, tax and invoice numbering all live here), so it
        // arriving looking unlike its siblings was the most visible seam.
        title: AppBarTitleRow(
          icon: Icons.receipt_long_rounded,
          color: AppTheme.successColor,
          title: 'Billing Settings',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
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
                    if (!canEdit) ...[
                      _readOnlyNote(context),
                      const SizedBox(height: 12),
                    ],
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
                      // Stacked on phones: side by side, each field was about
                      // 86 px wide and its label was cut off.
                      ResponsiveFormRow(
                        children: [
                          _field(
                            _businessPhoneCtrl,
                            'Phone',
                            Icons.phone_rounded,
                            keyboard: TextInputType.phone,
                          ),
                          _field(
                            _businessEmailCtrl,
                            'Email',
                            Icons.email_rounded,
                            keyboard: TextInputType.emailAddress,
                          ),
                        ],
                      ),
                      _field(_taxIdCtrl, 'Tax ID / GSTIN', Icons.badge_rounded),
                    ], anchor: 'billing.business'),
                    const SizedBox(height: 16),
                    _section('Tax Configuration', AppTheme.warningColor, [
                      ResponsiveFormRow(
                        children: [
                          _field(
                            _taxLabelCtrl,
                            'Tax Label (e.g. GST)',
                            Icons.label_rounded,
                          ),
                          _field(
                            _taxRateCtrl,
                            'Default Tax %',
                            Icons.percent_rounded,
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
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
                        onChanged: canEdit ? (v) => setState(() => _taxInclusive = v) : null,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ], anchor: 'billing.tax'),
                    const SizedBox(height: 16),
                    _section('Invoice Numbering', AppTheme.indigoColor, [
                      ResponsiveFormRow(
                        children: [
                          _field(
                            _prefixCtrl,
                            'Prefix (e.g. INV)',
                            Icons.tag_rounded,
                          ),
                          _field(
                            _nextNumCtrl,
                            'Next Number',
                            Icons.numbers_rounded,
                            keyboard: TextInputType.number,
                          ),
                        ],
                      ),
                      ResponsiveFormRow(
                        children: [
                          _field(
                            _currencyCtrl,
                            'Currency Symbol',
                            Icons.currency_rupee_rounded,
                          ),
                          DropdownButtonFormField<int>(
                            initialValue: _paymentTermDays,
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
                            onChanged: canEdit
                                ? (v) => setState(() => _paymentTermDays = v ?? 0)
                                : null,
                          ),
                        ],
                      ),
                    ], anchor: 'billing.numbering'),
                    const SizedBox(height: 16),
                    _section('Purchase Bill Numbering', AppTheme.warningColor, [
                      ResponsiveFormRow(
                        children: [
                          _field(
                            _purchasePrefixCtrl,
                            'Purchase Prefix (e.g. BILL)',
                            Icons.tag_rounded,
                          ),
                          _field(
                            _nextPurchaseNumCtrl,
                            'Next Purchase Number',
                            Icons.numbers_rounded,
                            keyboard: TextInputType.number,
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
                    ], anchor: 'billing.terms'),
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
                        onChanged: canEdit ? (v) => setState(() => _enableTax = v) : null,
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
                        onChanged: canEdit ? (v) => setState(() => _enableDiscounts = v) : null,
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
                        onChanged: canEdit
                            ? (v) => setState(() => _enablePaymentTracking = v)
                            : null,
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
                        onChanged: canEdit
                            ? (v) => setState(() => _autoCreateSoForStandaloneSales = v)
                            : null,
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
                        onChanged: canEdit
                            ? (v) => setState(() => _autoCreatePoForStandaloneBills = v)
                            : null,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]),
                  ],
                ),
              ),
              if (canEdit) _buildBottomBar(),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// These settings live on the company document, which only admins and
  /// people who may manage company settings can write. Everyone else used to
  /// get an editable form whose Save was always refused.
  bool _canEdit(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return !auth.isInspecting &&
        (auth.currentUser?.hasPermission(
              AppPermissions.manageCompanySettings,
            ) ??
            false);
  }

  Widget _readOnlyNote(BuildContext context) {
    final color = AppTheme.info(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only an admin, or someone who can manage company settings, can '
              'change these.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    Color color,
    List<Widget> children, {
    String? anchor,
  }) {
    final body = Column(
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
                  fontSize: 12,
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
    // Every section gets the same 4 px inset the search highlight needs; only
    // the anchored ones had it, so the cards' edges did not line up.
    final framed = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: anchor != null && isFlashing(anchor)
            ? AppTheme.tint(context, color)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: body,
    );
    if (anchor == null) return framed;
    return KeyedSubtree(key: keyFor(anchor), child: framed);
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
        readOnly: !_canEdit(context),
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
        child: ShimmerButton(
          label: _isSaving ? 'Saving…' : 'Save Settings',
          icon: Icons.save_rounded,
          onPressed: _isSaving ? null : _save,
        ),
      ),
    );
  }
}
