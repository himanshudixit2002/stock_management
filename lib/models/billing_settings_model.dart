import '../utils/parse_helpers.dart';

class BillingSettings {
  final bool billingEnabled;
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String businessEmail;
  final String taxId;
  final String taxLabel;
  final double defaultTaxRate;
  final bool taxInclusive;
  final String invoicePrefix;
  final int nextInvoiceNumber;
  final int defaultPaymentTermDays;
  final String invoiceFooter;
  final String currencySymbol;
  final bool enableTax;
  final bool enableDiscounts;
  final bool enablePaymentTracking;
  final String purchasePrefix;
  final int nextPurchaseNumber;
  final String defaultNotes;
  /// When true, saving a non-draft standalone sales invoice creates a dispatched SO linked to it.
  final bool autoCreateSalesOrderForStandaloneSales;
  /// When true, saving a non-draft standalone purchase bill creates a received PO linked to it.
  final bool autoCreatePurchaseOrderForStandaloneBills;

  const BillingSettings({
    this.billingEnabled = false,
    this.businessName = '',
    this.businessAddress = '',
    this.businessPhone = '',
    this.businessEmail = '',
    this.taxId = '',
    this.taxLabel = 'GST',
    this.defaultTaxRate = 0,
    this.taxInclusive = false,
    this.invoicePrefix = 'INV',
    this.nextInvoiceNumber = 1,
    this.defaultPaymentTermDays = 0,
    this.invoiceFooter = '',
    this.currencySymbol = '₹',
    this.enableTax = true,
    this.enableDiscounts = true,
    this.enablePaymentTracking = true,
    this.purchasePrefix = 'BILL',
    this.nextPurchaseNumber = 1,
    this.defaultNotes = '',
    this.autoCreateSalesOrderForStandaloneSales = true,
    this.autoCreatePurchaseOrderForStandaloneBills = true,
  });

  factory BillingSettings.fromMap(Map<String, dynamic> map) {
    return BillingSettings(
      billingEnabled: safeBool(map['billingEnabled']),
      businessName: safeString(map['businessName']),
      businessAddress: safeString(map['businessAddress']),
      businessPhone: safeString(map['businessPhone']),
      businessEmail: safeString(map['businessEmail']),
      taxId: safeString(map['taxId']),
      taxLabel: safeString(map['taxLabel'], 'GST'),
      defaultTaxRate: safeDouble(map['defaultTaxRate']),
      taxInclusive: safeBool(map['taxInclusive']),
      invoicePrefix: safeString(map['invoicePrefix'], 'INV'),
      nextInvoiceNumber: safeInt(map['nextInvoiceNumber'], 1),
      defaultPaymentTermDays: safeInt(map['defaultPaymentTermDays']),
      invoiceFooter: safeString(map['invoiceFooter']),
      currencySymbol: safeString(map['currencySymbol'], '₹'),
      enableTax: safeBool(map['enableTax'], true),
      enableDiscounts: safeBool(map['enableDiscounts'], true),
      enablePaymentTracking: safeBool(map['enablePaymentTracking'], true),
      purchasePrefix: safeString(map['purchasePrefix'], 'BILL'),
      nextPurchaseNumber: safeInt(map['nextPurchaseNumber'], 1),
      defaultNotes: safeString(map['defaultNotes']),
      autoCreateSalesOrderForStandaloneSales: safeBool(
        map['autoCreateSalesOrderForStandaloneSales'],
        true,
      ),
      autoCreatePurchaseOrderForStandaloneBills: safeBool(
        map['autoCreatePurchaseOrderForStandaloneBills'],
        true,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'billingEnabled': billingEnabled,
    'businessName': businessName,
    'businessAddress': businessAddress,
    'businessPhone': businessPhone,
    'businessEmail': businessEmail,
    'taxId': taxId,
    'taxLabel': taxLabel,
    'defaultTaxRate': defaultTaxRate,
    'taxInclusive': taxInclusive,
    'invoicePrefix': invoicePrefix,
    'nextInvoiceNumber': nextInvoiceNumber,
    'defaultPaymentTermDays': defaultPaymentTermDays,
    'invoiceFooter': invoiceFooter,
    'currencySymbol': currencySymbol,
    'enableTax': enableTax,
    'enableDiscounts': enableDiscounts,
    'enablePaymentTracking': enablePaymentTracking,
    'purchasePrefix': purchasePrefix,
    'nextPurchaseNumber': nextPurchaseNumber,
    'defaultNotes': defaultNotes,
    'autoCreateSalesOrderForStandaloneSales':
        autoCreateSalesOrderForStandaloneSales,
    'autoCreatePurchaseOrderForStandaloneBills':
        autoCreatePurchaseOrderForStandaloneBills,
  };

  BillingSettings copyWith({
    bool? billingEnabled,
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    String? taxId,
    String? taxLabel,
    double? defaultTaxRate,
    bool? taxInclusive,
    String? invoicePrefix,
    int? nextInvoiceNumber,
    int? defaultPaymentTermDays,
    String? invoiceFooter,
    String? currencySymbol,
    bool? enableTax,
    bool? enableDiscounts,
    bool? enablePaymentTracking,
    String? purchasePrefix,
    int? nextPurchaseNumber,
    String? defaultNotes,
    bool? autoCreateSalesOrderForStandaloneSales,
    bool? autoCreatePurchaseOrderForStandaloneBills,
  }) {
    return BillingSettings(
      billingEnabled: billingEnabled ?? this.billingEnabled,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessPhone: businessPhone ?? this.businessPhone,
      businessEmail: businessEmail ?? this.businessEmail,
      taxId: taxId ?? this.taxId,
      taxLabel: taxLabel ?? this.taxLabel,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      taxInclusive: taxInclusive ?? this.taxInclusive,
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      nextInvoiceNumber: nextInvoiceNumber ?? this.nextInvoiceNumber,
      defaultPaymentTermDays:
          defaultPaymentTermDays ?? this.defaultPaymentTermDays,
      invoiceFooter: invoiceFooter ?? this.invoiceFooter,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      enableTax: enableTax ?? this.enableTax,
      enableDiscounts: enableDiscounts ?? this.enableDiscounts,
      enablePaymentTracking:
          enablePaymentTracking ?? this.enablePaymentTracking,
      purchasePrefix: purchasePrefix ?? this.purchasePrefix,
      nextPurchaseNumber: nextPurchaseNumber ?? this.nextPurchaseNumber,
      defaultNotes: defaultNotes ?? this.defaultNotes,
      autoCreateSalesOrderForStandaloneSales:
          autoCreateSalesOrderForStandaloneSales ??
          this.autoCreateSalesOrderForStandaloneSales,
      autoCreatePurchaseOrderForStandaloneBills:
          autoCreatePurchaseOrderForStandaloneBills ??
          this.autoCreatePurchaseOrderForStandaloneBills,
    );
  }

  String formatInvoiceNumber(int number) {
    return '$invoicePrefix-${number.toString().padLeft(4, '0')}';
  }

  String formatPurchaseNumber(int number) {
    return '$purchasePrefix-${number.toString().padLeft(4, '0')}';
  }
}
