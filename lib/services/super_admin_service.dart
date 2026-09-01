import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/constants.dart';
import '../models/company_model.dart';
import '../models/company_plan_model.dart';

/// Cross-tenant operations for the super admin dashboard.
///
/// Every method here reaches across the company boundary that the rest of the
/// app is carefully fenced inside, so all of it is gated on the caller holding
/// a `superAdmins/{uid}` doc — enforced in firestore.rules, not here. This
/// class assumes nothing about the caller; if they are not a super admin the
/// reads and writes simply fail.
class SuperAdminService {
  SuperAdminService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection('companies');

  /// Whether [uid] is a super admin.
  ///
  /// The rules let a user read only their own doc here, so this cannot be used
  /// to probe for other people's privileges.
  Future<bool> isSuperAdmin(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final doc = await _firestore.collection('superAdmins').doc(uid).get();
      return doc.exists;
    } on FirebaseException {
      // A denied read means "not a super admin" as far as the UI is concerned.
      return false;
    }
  }

  /// Every company, newest first.
  Stream<List<CompanyModel>> watchCompanies() {
    return _companies
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => CompanyModel.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Future<CompanyModel?> getCompany(String companyId) async {
    final doc = await _companies.doc(companyId).get();
    if (!doc.exists) return null;
    return CompanyModel.fromMap(doc.data()!, doc.id);
  }

  /// Counts for one company via aggregation queries, so this never downloads a
  /// tenant's documents — the dashboard stays cheap however large they get.
  Future<CompanyStats> companyStats(String companyId) async {
    Future<int> countOf(String collection) async {
      try {
        final snap = await _companies
            .doc(companyId)
            .collection(collection)
            .count()
            .get();
        return snap.count ?? 0;
      } on FirebaseException {
        return 0;
      }
    }

    // Users live in a root collection keyed by companyId, not a subcollection.
    Future<int> userCount() async {
      try {
        final snap = await _firestore
            .collection('users')
            .where('companyId', isEqualTo: companyId)
            .count()
            .get();
        return snap.count ?? 0;
      } on FirebaseException {
        return 0;
      }
    }

    final results = await Future.wait([
      userCount(),
      countOf('products'),
      countOf('invoices'),
      countOf('salesOrders'),
      countOf('purchaseOrders'),
    ]);

    return CompanyStats(
      users: results[0],
      products: results[1],
      invoices: results[2],
      salesOrders: results[3],
      purchaseOrders: results[4],
    );
  }

  /// Moves a company onto [planId].
  ///
  /// Targeted field updates throughout this class: a company doc also carries a
  /// `settings` map owned by SettingsProvider and BillingSettingsProvider, and
  /// a whole-document write would silently drop it.
  Future<void> setPlan({
    required String companyId,
    required String planId,
    String note = '',
  }) async {
    final plan = CompanyPlan(
      planId: planId,
      status: PlanStatus.active,
      startedAt: DateTime.now(),
      note: note,
    );
    await _companies.doc(companyId).update({'plan': plan.toMap()});
  }

  /// Suspends, reactivates, or soft-deletes a company.
  ///
  /// Suspension and soft deletion are both reversible and take effect at once:
  /// `companyActive()` in the rules stops writes as soon as this lands.
  Future<void> setStatus({
    required String companyId,
    required CompanyStatus status,
    String note = '',
  }) async {
    await _companies.doc(companyId).update({
      'status': CompanyModel.statusToString(status),
      'statusNote': note,
      'statusChangedAt': Timestamp.now(),
    });
  }

  /// Subcollections a company owns. Kept in one place so a purge cannot
  /// silently miss one as the schema grows.
  static const List<String> companySubcollections = [
    'products',
    'categories',
    'transactions',
    'stockHolds',
    'vendors',
    'purchaseOrders',
    'salesOrders',
    'returns',
    'customers',
    'batches',
    'stockTakes',
    'auditLogs',
    'notifications',
    'priceHistory',
    'warehouseZones',
    'invoices',
    'billingSequences',
    'roles',
    'invites',
    'feedback',
    'members',
  ];

  /// Permanently deletes a company and everything under it.
  ///
  /// Irreversible, and this project has no backups — callers must confirm hard.
  /// Deliberately reachable only for a company that is already soft-deleted.
  ///
  /// This is client-driven and therefore interruptible: it deletes in batches
  /// and reports progress, but a dropped connection leaves the company
  /// partially purged (safe to re-run — it is idempotent). For a large tenant
  /// `firebase firestore:delete --recursive` is the more robust tool.
  Future<void> purgeCompany({
    required String companyId,
    void Function(String collection, int deleted)? onProgress,
  }) async {
    for (final name in companySubcollections) {
      final collection = _companies.doc(companyId).collection(name);
      var deleted = 0;
      while (true) {
        final snap = await collection.limit(kFirestoreBatchLimit).get();
        if (snap.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        deleted += snap.docs.length;
        onProgress?.call(name, deleted);
        // A short page means the collection is drained.
        if (snap.docs.length < kFirestoreBatchLimit) break;
      }
    }
    await _companies.doc(companyId).delete();
  }
}
