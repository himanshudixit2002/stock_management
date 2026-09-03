import 'dart:async';
import '../models/company_model.dart';
import '../models/company_plan_model.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/constants.dart';
import '../models/product_model.dart';
import '../services/company_settings_writer.dart';
import '../services/database_service.dart';
import '../services/stats_cache.dart';
import '../utils/error_helpers.dart';

class SettingsProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StatsCache _statsCache = StatsCache();
  String _companyId = '';
  bool _pricingEnabled = true;
  bool _vendorsEnabled = true;
  bool _barcodeEnabled = true;
  bool _initialized = false;

  /// The company doc itself, for its plan and lifecycle status. Null until the
  /// first load completes.
  CompanyModel? _company;

  /// The raw `settings` sub-map from the company doc, kept so other providers
  /// can reuse this read instead of fetching `companies/{id}` again. Null until
  /// the doc has been read successfully.
  Map<String, dynamic>? _rawSettings;
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

  CompanyModel? get company => _company;

  /// The raw `settings` map from the company doc, or null if it has not been
  /// read successfully yet. Callers that get null must fetch it themselves.
  Map<String, dynamic>? get rawSettings => _rawSettings;

  /// The plan this workspace is on. Free until proven otherwise, so the UI
  /// never renders a blank badge while the company doc is still loading.
  CompanyPlan get plan => _company?.plan ?? const CompanyPlan();

  /// False when the workspace has been suspended or deleted by a platform
  /// admin. Writes are already blocked by companyActive() in firestore.rules;
  /// this is what lets the app say so instead of surfacing permission errors.
  bool get isWorkspaceUsable => _company?.isUsable ?? true;

  CompanyStatus get workspaceStatus =>
      _company?.status ?? CompanyStatus.active;

  String get workspaceStatusNote => _company?.statusNote ?? '';
  String? get warningMessage => _warningMessage;
  List<String> get companies => List.unmodifiable(_companies);
  List<String> get sizes => List.unmodifiable(_sizes);
  List<String> get locations => List.unmodifiable(_locations);

  DocumentReference get _companyDoc =>
      _firestore.collection('companies').doc(_companyId);

  /// Writes into the nested `settings` map. See [CompanySettingsWriter] for
  /// why this must never be `set({'settings.x': ...}, merge: true)`.
  CompanySettingsWriter get _settingsWriter => CompanySettingsWriter(
    _firestore.collection('companies').doc(_companyId),
  );

  Future<void> _writeSetting(String key, Object? value) =>
      _settingsWriter.write(key, value);

  CollectionReference<Map<String, dynamic>> get _products =>
      _companyDoc.collection('products');

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _companyDoc.collection('transactions');

  String get companyId => _companyId;

  void reset() {
    _company = null;
    _rawSettings = null;
    _companyId = '';
    _pricingEnabled = true;
    _vendorsEnabled = true;
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
    _pricingEnabled = true;
    _vendorsEnabled = true;
    _barcodeEnabled = true;
    _companies = [];
    _sizes = [];
    _locations = [];
    _errorMessage = null;
    _rawSettings = null;

    // Seed feature toggles from the last-known cache so the Home grid gates
    // features correctly on first paint (no flash of actions that get hidden
    // once Firestore returns). Reconciled below with authoritative values.
    final cachedToggles = await _statsCache.readSettingsToggles(companyId);
    if (cachedToggles != null) {
      _pricingEnabled = cachedToggles.pricingEnabled;
      _vendorsEnabled = cachedToggles.vendorsEnabled;
      _barcodeEnabled = cachedToggles.barcodeEnabled;
      notifyListeners();
    }

    try {
      final doc = await _companyDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        // The company doc is already being read here, so pick up its lifecycle
        // status too rather than paying for a second read elsewhere.
        _company = CompanyModel.fromMap(data ?? const {}, doc.id);
        // The write path enforces the plan's caps, and this is the only place
        // the plan is read. Without this hand-off DatabaseService would keep
        // the uncapped default and every limit would be decorative.
        DatabaseService().setPlan(_company!.plan);
        // Recover anything the old broken write path stranded in top-level
        // `settings.*` fields before reading, so a workspace that has been
        // saving into the void gets its real values back on this load rather
        // than falling to defaults again.
        final healed = data == null
            ? null
            : await _settingsWriter.healFlatKeys(data);
        // Hand the raw map to [BillingSettingsProvider] so startup reads
        // `companies/{id}` once instead of twice.
        final settings =
            healed ?? data?['settings'] as Map<String, dynamic>? ?? const {};
        _rawSettings = settings;
        if (settings.isNotEmpty) {
          _pricingEnabled = settings['pricingEnabled'] != false;
          _vendorsEnabled = settings['vendorsEnabled'] != false;
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

    // Persist authoritative toggles for the next cold start. Fire-and-forget.
    unawaited(
      _statsCache.saveSettingsToggles(
        companyId,
        pricingEnabled: _pricingEnabled,
        vendorsEnabled: _vendorsEnabled,
        barcodeEnabled: _barcodeEnabled,
      ),
    );
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
      await _writeSetting('pricingEnabled', enabled);
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
      await _writeSetting('vendorsEnabled', enabled);
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
      await _writeSetting('barcodeEnabled', enabled);
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
      await _writeSetting('companies', FieldValue.arrayUnion([trimmed]));
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
      await _writeSetting('companies', FieldValue.arrayRemove([actual]));
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
      // One write: arrayRemove then arrayUnion were two round-trips, and a
      // failure between them dropped the company from settings entirely.
      await _writeSetting('companies', List<String>.from(_companies));
      var page = await _products
          .where('company', isEqualTo: actual)
          .limit(kFirestoreBatchLimit)
          .get();
      while (page.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.update(doc.reference, {'company': newTrimmed});
        }
        await batch.commit();
        if (page.docs.length < kFirestoreBatchLimit) break;
        // No cursor: the documents just written no longer match the filter, so
        // re-running the query returns the remainder. Positioning
        // startAfterDocument on a document that has left the result set is
        // undefined, and it could skip products past the first page.
        page = await _products
            .where('company', isEqualTo: actual)
            .limit(kFirestoreBatchLimit)
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
      await _writeSetting('companies', FieldValue.arrayUnion(toAdd));
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
      await _writeSetting('sizes', FieldValue.arrayUnion([trimmed]));
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
      await _writeSetting('sizes', FieldValue.arrayRemove([actual]));
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
      // One write — see renameCompany.
      await _writeSetting('sizes', List<String>.from(_sizes));
      var page = await _products
          .where('size', isEqualTo: actual)
          .limit(kFirestoreBatchLimit)
          .get();
      while (page.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.update(doc.reference, {'size': newTrimmed});
        }
        await batch.commit();
        if (page.docs.length < kFirestoreBatchLimit) break;
        // No cursor — the updated documents leave the filter, so re-running
        // returns the remainder. See renameCompany.
        page = await _products
            .where('size', isEqualTo: actual)
            .limit(kFirestoreBatchLimit)
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
      await _writeSetting('sizes', FieldValue.arrayUnion(toAdd));
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
      await _writeSetting('locations', FieldValue.arrayUnion([trimmed]));
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
      await _writeSetting('locations', FieldValue.arrayRemove([actual]));
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
      // One write, not arrayRemove followed by arrayUnion. Those were two
      // separate round-trips, and a failure between them dropped the location
      // from settings altogether.
      await _writeSetting('locations', List<String>.from(_locations));

      // Products: move both the stock and the reservations at this location.
      //
      // No startAfterDocument cursor here. An updated document no longer
      // carries the old key, so it drops straight out of the filter and the
      // next unpaged query naturally returns the remainder. Paging with a
      // cursor positioned on a document that has left the result set is
      // undefined, and it silently skipped products past the first page.
      await _renameProductLocationKey(
        'locationQuantities',
        actual,
        newTrimmed,
      );
      // heldLocationQuantities was never migrated, so every reservation was
      // left pointing at a name that no longer held any stock — which the app's
      // own Data Health scan then reported as critical, and which stopped
      // despatch resolving its holds.
      await _renameProductLocationKey(
        'heldLocationQuantities',
        actual,
        newTrimmed,
      );

      // Stock holds carry their own location field.
      await _renameHoldLocations(actual, newTrimmed);

      // Transactions: exact match only.
      //
      // This used to select on `loc.contains(actual)` and rewrite with
      // `replaceAll`, so renaming "A" to "Zone-1" turned "Warehouse A" into
      // "Warehouse Zone-1" and "AISLE-3" into "Zone-1ISLE-3" — corrupting the
      // history of locations the user never touched. renameCompany had always
      // done this correctly with an equality filter.
      var txnPage = await _transactions
          .where('location', isEqualTo: actual)
          .limit(kFirestoreBatchLimit)
          .get();
      while (txnPage.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in txnPage.docs) {
          batch.update(doc.reference, {'location': newTrimmed});
        }
        await batch.commit();
        if (txnPage.docs.length < kFirestoreBatchLimit) break;
        txnPage = await _transactions
            .where('location', isEqualTo: actual)
            .limit(kFirestoreBatchLimit)
            .get();
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

  /// Moves a key inside one of the products' location maps.
  ///
  /// [path] addresses the specific key (`locationQuantities.<old>` or
  /// `heldLocationQuantities.<old>`) so only products that actually use it are
  /// read. The whole map is rewritten rather than using a dotted shorthand,
  /// because a location name containing a dot would otherwise be taken as a
  /// field path and write a nested map that reads back as zero.
  Future<void> _renameProductLocationKey(
    String field,
    String from,
    String to,
  ) async {
    final path = FieldPath([field, from]);
    var page = await _products
        .where(path, isNotEqualTo: null)
        .limit(kFirestoreBatchLimit)
        .get();
    while (page.docs.isNotEmpty) {
      final batch = _firestore.batch();
      var writes = 0;
      for (final doc in page.docs) {
        final raw = doc.data()[field];
        final map = Map<String, dynamic>.from(raw is Map ? raw : {});
        final qty = map.remove(from);
        if (qty == null) continue;
        final qtyInt = qty is int ? qty : (qty as num).toInt();
        final existing = map[to];
        final existingInt = existing == null
            ? 0
            : (existing is int ? existing : (existing as num).toInt());
        map[to] = existingInt + qtyInt;
        batch.update(doc.reference, {field: map});
        writes++;
      }
      if (writes > 0) await batch.commit();
      if (page.docs.length < kFirestoreBatchLimit) break;
      // Re-query without a cursor: the documents just written no longer match
      // the filter, so the next page is the remainder.
      page = await _products
          .where(path, isNotEqualTo: null)
          .limit(kFirestoreBatchLimit)
          .get();
    }
  }

  /// Repoints stock holds recorded against [from].
  ///
  /// Holds keep their own `location`, and it was never migrated — so after a
  /// rename every reservation referred to a place that no longer had any stock.
  Future<void> _renameHoldLocations(String from, String to) async {
    final holds = _companyDoc.collection('stockHolds');
    var page = await holds
        .where('location', isEqualTo: from)
        .limit(kFirestoreBatchLimit)
        .get();
    while (page.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in page.docs) {
        batch.update(doc.reference, {'location': to});
      }
      await batch.commit();
      if (page.docs.length < kFirestoreBatchLimit) break;
      page = await holds
          .where('location', isEqualTo: from)
          .limit(kFirestoreBatchLimit)
          .get();
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
      await _writeSetting('locations', FieldValue.arrayUnion(toAdd));
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
