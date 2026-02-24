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
  List<String> _companies = [];
  List<String> _sizes = [];
  List<String> _locations = [];

  bool get pricingEnabled => _pricingEnabled;
  bool get vendorsEnabled => _vendorsEnabled;
  bool get isInitialized => _initialized;
  String? get errorMessage => _errorMessage;
  List<String> get companies => List.unmodifiable(_companies);
  List<String> get sizes => List.unmodifiable(_sizes);
  List<String> get locations => List.unmodifiable(_locations);

  DocumentReference get _companyDoc =>
      _firestore.collection('companies').doc(_companyId);

  Future<void> initialize(String companyId) async {
    _companyId = companyId;
    _pricingEnabled = false;
    _vendorsEnabled = false;
    _companies = [];
    _sizes = [];
    _locations = [];
    _errorMessage = null;
    try {
      final doc = await _companyDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('settings')) {
          final settings = data['settings'] as Map<String, dynamic>? ?? {};
          _pricingEnabled = settings['pricingEnabled'] == true;
          _vendorsEnabled = settings['vendorsEnabled'] == true;
          _companies = _toStringList(settings['companies']);
          _sizes = _toStringList(settings['sizes']);
          _locations = _toStringList(settings['locations']);
        }
      }
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not load settings.');
    }
    _initialized = true;
    notifyListeners();
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  // --- Toggle helpers ---

  Future<bool> togglePricing(bool enabled) async {
    if (_companyId.isEmpty) {
      _errorMessage = 'Settings not initialized. Please restart the app.';
      notifyListeners();
      return false;
    }
    final previous = _pricingEnabled;
    _pricingEnabled = enabled;
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
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
    if (_companyId.isEmpty) {
      _errorMessage = 'Settings not initialized. Please restart the app.';
      notifyListeners();
      return false;
    }
    final previous = _vendorsEnabled;
    _vendorsEnabled = enabled;
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
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

  // --- Company list CRUD ---

  Future<bool> addCompany(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        _companies.any((c) => c.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    _companies.add(trimmed);
    _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'companies': FieldValue.arrayUnion([trimmed])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _companies.remove(trimmed);
      _errorMessage = friendlyError(e, fallback: 'Failed to add company.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeCompany(String name) async {
    if (!_companies.contains(name)) return false;
    _companies.remove(name);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'companies': FieldValue.arrayRemove([name])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _companies.add(name);
      _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove company.');
      notifyListeners();
      return false;
    }
  }

  // --- Size list CRUD ---

  Future<bool> addSize(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        _sizes.any((s) => s.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    _sizes.add(trimmed);
    _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'sizes': FieldValue.arrayUnion([trimmed])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _sizes.remove(trimmed);
      _errorMessage = friendlyError(e, fallback: 'Failed to add size.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeSize(String name) async {
    if (!_sizes.contains(name)) return false;
    _sizes.remove(name);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'sizes': FieldValue.arrayRemove([name])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _sizes.add(name);
      _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove size.');
      notifyListeners();
      return false;
    }
  }

  // --- Location list CRUD ---

  Future<bool> addLocation(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        _locations.any((l) => l.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    _locations.add(trimmed);
    _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'locations': FieldValue.arrayUnion([trimmed])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _locations.remove(trimmed);
      _errorMessage = friendlyError(e, fallback: 'Failed to add location.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeLocation(String name) async {
    if (!_locations.contains(name)) return false;
    _locations.remove(name);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'locations': FieldValue.arrayRemove([name])},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _locations.add(name);
      _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove location.');
      notifyListeners();
      return false;
    }
  }
}
