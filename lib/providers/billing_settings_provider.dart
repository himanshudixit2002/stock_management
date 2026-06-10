import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/billing_settings_model.dart';
import '../utils/error_helpers.dart';

class BillingSettingsProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  Future<void> initialize(String companyId) async {
    _companyId = companyId;
    _settings = const BillingSettings();
    _errorMessage = null;
    try {
      final doc = await _companyDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final billing = data?['settings']?['billing'] as Map<String, dynamic>?;
        if (billing != null) {
          _settings = BillingSettings.fromMap(billing);
        }
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
      await _companyDoc.set({
        'settings.billing.billingEnabled': enabled,
      }, SetOptions(merge: true));
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
      await _companyDoc.set({
        'settings.billing': updated.toMap(),
      }, SetOptions(merge: true));
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
