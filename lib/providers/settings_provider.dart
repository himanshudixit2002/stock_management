import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
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
        'settings': {
          'companies': FieldValue.arrayUnion([trimmed]),
        },
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
    final idx = _companies.indexWhere(
      (c) => c.toLowerCase() == name.toLowerCase(),
    );
    if (idx == -1) return false;
    final actual = _companies[idx];
    _companies.removeAt(idx);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'companies': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _companies.add(actual);
      _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove company.');
      notifyListeners();
      return false;
    }
  }

  /// Batch add companies from import. Only adds values not already in Settings.
  Future<bool> addCompaniesFromImport(List<String> names) async {
    if (_companyId.isEmpty) return false;
    final existing = _companies.map((c) => c.toLowerCase()).toSet();
    final toAdd = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty && !existing.contains(n.toLowerCase()))
        .toSet()
        .toList();
    if (toAdd.isEmpty) return true;
    for (final n in toAdd) {
      _companies.add(n);
      existing.add(n.toLowerCase());
    }
    _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'companies': FieldValue.arrayUnion(toAdd)},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      for (final n in toAdd) {
        _companies.remove(n);
      }
      _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to add companies.');
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
        'settings': {
          'sizes': FieldValue.arrayUnion([trimmed]),
        },
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
    final idx = _sizes.indexWhere((s) => s.toLowerCase() == name.toLowerCase());
    if (idx == -1) return false;
    final actual = _sizes[idx];
    _sizes.removeAt(idx);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'sizes': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _sizes.add(actual);
      _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove size.');
      notifyListeners();
      return false;
    }
  }

  /// Batch add sizes from import. Only adds values not already in Settings.
  Future<bool> addSizesFromImport(List<String> names) async {
    if (_companyId.isEmpty) return false;
    final existing = _sizes.map((s) => s.toLowerCase()).toSet();
    final toAdd = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty && !existing.contains(n.toLowerCase()))
        .toSet()
        .toList();
    if (toAdd.isEmpty) return true;
    for (final n in toAdd) {
      _sizes.add(n);
      existing.add(n.toLowerCase());
    }
    _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'sizes': FieldValue.arrayUnion(toAdd)},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      for (final n in toAdd) {
        _sizes.remove(n);
      }
      _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to add sizes.');
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
        'settings': {
          'locations': FieldValue.arrayUnion([trimmed]),
        },
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
    final idx = _locations.indexWhere(
      (l) => l.toLowerCase() == name.toLowerCase(),
    );
    if (idx == -1) return false;
    final actual = _locations[idx];
    _locations.removeAt(idx);
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'locations': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _locations.add(actual);
      _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to remove location.');
      notifyListeners();
      return false;
    }
  }

  /// Batch add locations from import. Only adds values not already in Settings.
  Future<bool> addLocationsFromImport(List<String> names) async {
    if (_companyId.isEmpty) return false;
    final existing = _locations.map((l) => l.toLowerCase()).toSet();
    final toAdd = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty && !existing.contains(n.toLowerCase()))
        .toSet()
        .toList();
    if (toAdd.isEmpty) return true;
    for (final n in toAdd) {
      _locations.add(n);
      existing.add(n.toLowerCase());
    }
    _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'locations': FieldValue.arrayUnion(toAdd)},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      for (final n in toAdd) {
        _locations.remove(n);
      }
      _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to add locations.');
      notifyListeners();
      return false;
    }
  }

  /// Sync companies, locations, sizes from an existing product list into Settings.
  /// Use for backfilling after imports done before sync was implemented.
  Future<bool> syncFromProductList(List<ProductModel> products) async {
    final companies = products
        .map((p) => p.company)
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList();
    final locations = products
        .expand((p) => p.locationQuantities.keys)
        .where((l) => l.trim().isNotEmpty)
        .toSet()
        .toList();
    final sizes = products
        .map((p) => p.size)
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    if (companies.isNotEmpty) await addCompaniesFromImport(companies);
    if (locations.isNotEmpty) await addLocationsFromImport(locations);
    if (sizes.isNotEmpty) await addSizesFromImport(sizes);
    return true;
  }
}
