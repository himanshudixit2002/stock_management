import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/company_plan_model.dart';
import '../services/plan_catalog_service.dart';

/// The live tier catalog.
///
/// [PlanCatalog] itself stays a synchronous global, because
/// `CompanyPlan.definition`, `PlanLimits` and a dozen widgets read it inline.
/// This provider owns the *subscription* and the rebuild signal: hydrating the
/// global alone changed no pixels, since nothing was listening to it.
///
/// (The first version signalled changes with a `setState` on the app shell.
/// That silently did nothing: the shell returns `const SuperAdminShell()`, and
/// Flutter skips the subtree when the new widget is identical to the old one.)
class PlanCatalogProvider extends ChangeNotifier {
  PlanCatalogProvider({PlanCatalogService? service})
    : _service = service ?? PlanCatalogService();

  final PlanCatalogService _service;

  StreamSubscription? _subscription;
  bool _loaded = false;
  String? _error;
  bool _busy = false;

  /// Every tier, in display order. Mirrors [PlanCatalog.all] — read through the
  /// provider so the widget rebuilds when it changes.
  List<PlanDefinition> get plans => PlanCatalog.all;

  /// Tiers that may be assigned to a workspace today.
  List<PlanDefinition> get assignable => PlanCatalog.assignable;

  /// True once a snapshot has arrived. Until then the compiled seed is showing.
  bool get loaded => _loaded;

  /// Why the catalog could not be read, or null. Never blocks the UI: the
  /// compiled tiers stay in place.
  String? get error => _error;

  /// True while a save, delete or seed is in flight.
  bool get busy => _busy;

  /// Starts streaming `plans/{id}`. Idempotent.
  void start() {
    if (_subscription != null) return;
    try {
      _subscription = _service.watchPlans().listen(
        (published) {
          PlanCatalog.hydrate(published);
          _loaded = true;
          _error = null;
          notifyListeners();
        },
        onError: (Object e) {
          // The seed catalog stands; the console shows why it is not live.
          _error = 'Could not read the published tiers.';
          notifyListeners();
        },
      );
    } catch (_) {
      // Firebase not ready. The compiled tiers remain usable.
      _error = 'Could not read the published tiers.';
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _loaded = false;
    _error = null;
  }

  Future<bool> savePlan(PlanDefinition plan) =>
      _run(() => _service.savePlan(plan));

  Future<bool> deletePlan(String planId) =>
      _run(() => _service.deletePlan(planId));

  /// Publishes the compiled tiers if nothing has been published yet.
  ///
  /// Returns null on failure so the caller can tell "wrote nothing because the
  /// catalog already exists" from "could not write".
  Future<bool?> seedIfEmpty() async {
    _busy = true;
    notifyListeners();
    try {
      return await _service.seedIfEmpty();
    } catch (_) {
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      // The snapshot listener delivers the new catalog, including the local
      // pending write, so no manual refresh is needed here.
      return true;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Drops the published catalog and returns to the compiled tiers.
  void reset() {
    stop();
    PlanCatalog.resetToSeed();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
