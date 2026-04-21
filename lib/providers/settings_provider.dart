import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/constants.dart';
import '../models/product_model.dart';
import '../utils/error_helpers.dart';

class SettingsProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _companyId = '';
  bool _pricingEnabled = false;
  bool _vendorsEnabled = false;
  bool _barcodeEnabled = true;
  bool _initialized = false;
  String? _errorMessage;
  String? _warningMessage;
  List<String> _companies = [];
  List<String> _sizes = [];
  List<String> _locations = [];

  bool get pricingEnabled => _pricingEnabled;
  bool get vendorsEnabled => _vendorsEnabled;
  bool get barcodeEnabled => _barcodeEnabled;
  bool get isInitialized => _initialized;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;
  List<String> get companies => List.unmodifiable(_companies);
  List<String> get sizes => List.unmodifiable(_sizes);
  List<String> get locations => List.unmodifiable(_locations);

  DocumentReference get _companyDoc =>
      _firestore.collection('companies').doc(_companyId);

  CollectionReference<Map<String, dynamic>> get _products =>
      _companyDoc.collection('products');

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _companyDoc.collection('transactions');

  String get companyId => _companyId;

  void reset() {
    _companyId = '';
    _pricingEnabled = false;
    _vendorsEnabled = false;
    _barcodeEnabled = true;
    _initialized = false;
    _errorMessage = null;
    _warningMessage = null;
    _companies = [];
    _sizes = [];
    _locations = [];
    notifyListeners();
  }

  void setWarning(String message) {
    _warningMessage = message;
    notifyListeners();
  }

  void clearWarning() {
    _warningMessage = null;
    notifyListeners();
  }

  Future<void> initialize(String companyId) async {
    _companyId = companyId;
    _pricingEnabled = false;
    _vendorsEnabled = false;
    _barcodeEnabled = true;
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
          _barcodeEnabled = settings['barcodeEnabled'] != false;
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

  Future<bool> toggleBarcode(bool enabled) async {
    if (_companyId.isEmpty) {
      _errorMessage = 'Settings not initialized. Please restart the app.';
      notifyListeners();
      return false;
    }
    final previous = _barcodeEnabled;
    _barcodeEnabled = enabled;
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {'barcodeEnabled': enabled},
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _barcodeEnabled = previous;
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

  /// Rename a company everywhere: settings, and all products using it.
  Future<bool> renameCompany(String oldName, String newName) async {
    if (_companyId.isEmpty) return false;
    final newTrimmed = newName.trim();
    if (newTrimmed.isEmpty) return false;
    final idx = _companies.indexWhere(
      (c) => c.toLowerCase() == oldName.trim().toLowerCase(),
    );
    if (idx == -1) return false;
    if (_companies.any((c) => c.toLowerCase() == newTrimmed.toLowerCase())) {
      _errorMessage = 'A company with that name already exists.';
      notifyListeners();
      return false;
    }
    final actual = _companies[idx];
    _companies[idx] = newTrimmed;
    _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'companies': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      await _companyDoc.set({
        'settings': {
          'companies': FieldValue.arrayUnion([newTrimmed]),
        },
      }, SetOptions(merge: true));
      var lastDoc = await _products
          .where('company', isEqualTo: actual)
          .limit(kFirestoreBatchLimit)
          .get();
      while (lastDoc.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in lastDoc.docs) {
          batch.update(doc.reference, {'company': newTrimmed});
        }
        await batch.commit();
        if (lastDoc.docs.length < kFirestoreBatchLimit) break;
        lastDoc = await _products
            .where('company', isEqualTo: actual)
            .limit(kFirestoreBatchLimit)
            .startAfterDocument(lastDoc.docs.last)
            .get();
      }
      return true;
    } catch (e) {
      _companies[idx] = actual;
      _companies.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to rename company.');
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

  /// Rename a size everywhere: settings, and all products using it.
  Future<bool> renameSize(String oldName, String newName) async {
    if (_companyId.isEmpty) return false;
    final newTrimmed = newName.trim();
    if (newTrimmed.isEmpty) return false;
    final idx = _sizes.indexWhere(
      (s) => s.toLowerCase() == oldName.trim().toLowerCase(),
    );
    if (idx == -1) return false;
    if (_sizes.any((s) => s.toLowerCase() == newTrimmed.toLowerCase())) {
      _errorMessage = 'A size with that name already exists.';
      notifyListeners();
      return false;
    }
    final actual = _sizes[idx];
    _sizes[idx] = newTrimmed;
    _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'sizes': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      await _companyDoc.set({
        'settings': {
          'sizes': FieldValue.arrayUnion([newTrimmed]),
        },
      }, SetOptions(merge: true));
      var lastDoc = await _products
          .where('size', isEqualTo: actual)
          .limit(kFirestoreBatchLimit)
          .get();
      while (lastDoc.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in lastDoc.docs) {
          batch.update(doc.reference, {'size': newTrimmed});
        }
        await batch.commit();
        if (lastDoc.docs.length < kFirestoreBatchLimit) break;
        lastDoc = await _products
            .where('size', isEqualTo: actual)
            .limit(kFirestoreBatchLimit)
            .startAfterDocument(lastDoc.docs.last)
            .get();
      }
      return true;
    } catch (e) {
      _sizes[idx] = actual;
      _sizes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to rename size.');
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

  /// Rename a location everywhere: settings, all products' locationQuantities, and all transactions.
  Future<bool> renameLocation(String oldName, String newName) async {
    if (_companyId.isEmpty) return false;
    final newTrimmed = newName.trim();
    if (newTrimmed.isEmpty) return false;
    final idx = _locations.indexWhere(
      (l) => l.toLowerCase() == oldName.trim().toLowerCase(),
    );
    if (idx == -1) return false;
    if (_locations.any((l) => l.toLowerCase() == newTrimmed.toLowerCase())) {
      _errorMessage = 'A location with that name already exists.';
      notifyListeners();
      return false;
    }
    final actual = _locations[idx];
    _locations[idx] = newTrimmed;
    _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _errorMessage = null;
    notifyListeners();
    try {
      await _companyDoc.set({
        'settings': {
          'locations': FieldValue.arrayRemove([actual]),
        },
      }, SetOptions(merge: true));
      await _companyDoc.set({
        'settings': {
          'locations': FieldValue.arrayUnion([newTrimmed]),
        },
      }, SetOptions(merge: true));

      final locPath = FieldPath(['locationQuantities', actual]);
      var lastDoc = await _products
          .where(locPath, isNotEqualTo: null)
          .limit(kFirestoreBatchLimit)
          .get();
      while (lastDoc.docs.isNotEmpty) {
        final batch = _firestore.batch();
        var batchCount = 0;
        for (final doc in lastDoc.docs) {
          final data = doc.data();
          final locQty = Map<String, dynamic>.from(
            data['locationQuantities'] is Map
                ? data['locationQuantities'] as Map
                : {},
          );
          final qty = locQty[actual];
          if (qty != null) {
            locQty.remove(actual);
            final qtyInt = qty is int ? qty : (qty as num).toInt();
            locQty[newTrimmed] = (locQty[newTrimmed] as int? ?? 0) + qtyInt;
            batch.update(doc.reference, {'locationQuantities': locQty});
            batchCount++;
          }
        }
        if (batchCount > 0) await batch.commit();
        if (lastDoc.docs.length < kFirestoreBatchLimit) break;
        lastDoc = await _products
            .where(locPath, isNotEqualTo: null)
            .limit(kFirestoreBatchLimit)
            .startAfterDocument(lastDoc.docs.last)
            .get();
      }

      DocumentSnapshot? lastTxnDoc;
      while (true) {
        Query<Map<String, dynamic>> q = _transactions
            .orderBy(FieldPath.documentId)
            .limit(kFirestoreBatchLimit);
        if (lastTxnDoc != null) {
          q = q.startAfterDocument(lastTxnDoc);
        }
        final txnSnap = await q.get();
        if (txnSnap.docs.isEmpty) break;
        final toUpdate = txnSnap.docs.where((d) {
          final loc = d.data()['location']?.toString() ?? '';
          return loc.contains(actual);
        }).toList();
        if (toUpdate.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in toUpdate) {
            final loc = doc.data()['location']?.toString() ?? '';
            final newLoc = loc.replaceAll(actual, newTrimmed);
            batch.update(doc.reference, {'location': newLoc});
          }
          await batch.commit();
        }
        if (txnSnap.docs.length < kFirestoreBatchLimit) break;
        lastTxnDoc = txnSnap.docs.last;
      }
      return true;
    } catch (e) {
      _locations[idx] = actual;
      _locations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _errorMessage = friendlyError(e, fallback: 'Failed to rename location.');
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
