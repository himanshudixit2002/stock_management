import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/billing_settings_model.dart';
import '../services/company_settings_writer.dart';
import '../utils/error_helpers.dart';

class BillingSettingsProvider extends ChangeNotifier {
  // Resolved on first use rather than at construction: this provider is built
  // during app startup, and on web Firebase is initialized a frame later. Also
  // lets tests construct it without a Firebase app.
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _companyId = '';
  BillingSettings _settings = const BillingSettings();
  bool _initialized = false;
  String? _errorMessage;

  BillingSettings get settings => _settings;
  bool get isInitialized => _initialized;
  String? get errorMessage => _errorMessage;
  bool get billingEnabled => _settings.billingEnabled;

  DocumentReference get _companyDoc =>
      _firestore.collection('companies').doc(_companyId);

  void reset() {
    _companyId = '';
    _settings = const BillingSettings();
    _initialized = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Merges [fields] into the company doc's nested `settings.billing` map.
  ///
  /// These writes used to be `set({'settings.billing': ...}, merge: true)`,
  /// which Firestore takes as a literal top-level field name rather than a
  /// path — so the currency symbol, invoice prefixes, GST numbers and terms all
  /// appeared to save and were gone on the next load. See
  /// [CompanySettingsWriter].
  Future<void> _writeBilling(Map<String, dynamic> fields) =>
      CompanySettingsWriter(
        _firestore.collection('companies').doc(_companyId),
      ).writeAll(fields, prefix: 'billing');

  /// Loads billing settings for [companyId].
  ///
  /// [companySettings] is the `settings` map from `companies/{companyId}` when
  /// the caller has already read that doc — startup does, via
  /// [SettingsProvider] — so passing it avoids a second read of the same
  /// document. Omit it and this fetches the doc itself.
  Future<void> initialize(
    String companyId, {
    Map<String, dynamic>? companySettings,
  }) async {
    _companyId = companyId;
    _settings = const BillingSettings();
    _errorMessage = null;
    try {
      Map<String, dynamic>? billing;
      if (companySettings != null) {
        billing = companySettings['billing'] as Map<String, dynamic>?;
      } else {
        final doc = await _companyDoc.get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          billing = data?['settings']?['billing'] as Map<String, dynamic>?;
        }
      }
      if (billing != null) {
        _settings = BillingSettings.fromMap(billing);
      }
      final seqSnap = await _companyDoc
          .collection('billingSequences')
          .doc('default')
          .get();
      if (seqSnap.exists && seqSnap.data() != null) {
        final s = seqSnap.data()!;
        _settings = _settings.copyWith(
          nextInvoiceNumber:
              (s['nextInvoiceNumber'] as num?)?.toInt() ??
              _settings.nextInvoiceNumber,
          nextPurchaseNumber:
              (s['nextPurchaseNumber'] as num?)?.toInt() ??
              _settings.nextPurchaseNumber,
        );
      }
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not load billing settings.',
      );
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> toggleBilling(bool enabled) async {
    if (_companyId.isEmpty) return false;
    final previous = _settings;
    _settings = _settings.copyWith(billingEnabled: enabled);
    _errorMessage = null;
    notifyListeners();
    try {
      await _writeBilling({'billingEnabled': enabled});
      return true;
    } catch (e) {
      _settings = previous;
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to update billing settings.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSettings(BillingSettings updated) async {
    if (_companyId.isEmpty) return false;
    final previous = _settings;
    _settings = updated;
    _errorMessage = null;
    notifyListeners();
    try {
      await _writeBilling(updated.toMap());
      await _companyDoc.collection('billingSequences').doc('default').set({
        'nextInvoiceNumber': updated.nextInvoiceNumber,
        'nextPurchaseNumber': updated.nextPurchaseNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _settings = previous;
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to save billing settings.',
      );
      notifyListeners();
      return false;
    }
  }
}
