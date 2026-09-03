import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_plan_model.dart';

/// Reads and writes the platform's tier catalog.
///
/// The tiers used to be `const` in [PlanCatalog], so changing a price meant a
/// code change and a redeploy. They now live in a root `plans` collection that
/// the platform console edits; the compiled tiers remain as the seed and the
/// offline fallback.
///
/// `plans` is world-readable in the security rules — a price list is public
/// information, and the signed-out register screen needs it — and writable only
/// by a platform admin.
class PlanCatalogService {
  PlanCatalogService({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  /// Resolved lazily so a subclass can be constructed in a test without
  /// Firebase being initialised.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _firestore.collection('plans');

  /// Every tier, live.
  ///
  /// A document that cannot be parsed is skipped rather than allowed to throw:
  /// one bad edit in the console must not take the catalog offline for every
  /// tenant.
  Stream<List<PlanDefinition>> watchPlans() {
    return _plans.snapshots().map((snap) {
      final out = <PlanDefinition>[];
      for (final doc in snap.docs) {
        try {
          out.add(PlanDefinition.fromMap(doc.data(), doc.id));
        } catch (_) {
          // Skip the malformed tier, keep the rest.
        }
      }
      return out;
    });
  }

  Future<List<PlanDefinition>> fetchPlans() async {
    final snap = await _plans.get();
    final out = <PlanDefinition>[];
    for (final doc in snap.docs) {
      try {
        out.add(PlanDefinition.fromMap(doc.data(), doc.id));
      } catch (_) {
        // As above.
      }
    }
    return out;
  }

  /// Creates or updates one tier.
  Future<void> savePlan(PlanDefinition plan) {
    return _plans.doc(plan.id).set(plan.toMap());
  }

  /// Removes a tier outright.
  ///
  /// Prefer archiving: [PlanCatalog.byId] falls back to MAX for an unknown id,
  /// so deleting a tier that workspaces are still on quietly promotes them.
  Future<void> deletePlan(String planId) => _plans.doc(planId).delete();

  /// Writes the compiled tiers if the collection is empty.
  ///
  /// Idempotent, and never overwrites an edited catalog — it only fills in a
  /// database that has never had one.
  Future<bool> seedIfEmpty() async {
    final snap = await _plans.limit(1).get();
    if (snap.docs.isNotEmpty) return false;
    final batch = _firestore.batch();
    for (var i = 0; i < PlanCatalog.seedDefaults.length; i++) {
      final plan = PlanCatalog.seedDefaults[i];
      batch.set(_plans.doc(plan.id), plan.copyWith(sortOrder: i).toMap());
    }
    await batch.commit();
    return true;
  }
}
