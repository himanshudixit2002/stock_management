import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/error_helpers.dart';

class SettingsProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _companyId = '';
  bool _pricingEnabled = false;
  bool _vendorsEnabled = false;
  bool _initialized = false;
  String? _errorMessage;

  bool get pricingEnabled => _pricingEnabled;
  bool get vendorsEnabled => _vendorsEnabled;
  bool get isInitialized => _initialized;
  String? get errorMessage => _errorMessage;

  Future<void> initialize(String companyId) async {
    _companyId = companyId;
    try {
      final doc = await _firestore.collection('companies').doc(companyId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('settings')) {
          final settings = data['settings'] as Map<String, dynamic>? ?? {};
          _pricingEnabled = settings['pricingEnabled'] == true;
          _vendorsEnabled = settings['vendorsEnabled'] == true;
        }
      }
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not load settings.');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> togglePricing(bool enabled) async {
    if (_companyId.isEmpty) return false;
    final previous = _pricingEnabled;
    _pricingEnabled = enabled;
    _errorMessage = null;
    notifyListeners();
    try {
      await _firestore.collection('companies').doc(_companyId).set({
        'settings': {'pricingEnabled': enabled},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _pricingEnabled = previous;
      _errorMessage = friendlyError(e, fallback: 'Failed to update settings.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleVendors(bool enabled) async {
    if (_companyId.isEmpty) return false;
    final previous = _vendorsEnabled;
    _vendorsEnabled = enabled;
    _errorMessage = null;
    notifyListeners();
    try {
      await _firestore.collection('companies').doc(_companyId).set({
        'settings': {'vendorsEnabled': enabled},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _vendorsEnabled = previous;
      _errorMessage = friendlyError(e, fallback: 'Failed to update settings.');
      notifyListeners();
      return false;
    }
  }
}
