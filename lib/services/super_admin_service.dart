import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/constants.dart';
import '../models/company_model.dart';
import '../models/company_plan_model.dart';
import '../models/role_model.dart';

/// Who performed a platform action, for the audit trail.
class PlatformActor {
  const PlatformActor({required this.uid, required this.email});

  final String uid;
  final String email;
}

/// One page of raw Firestore documents, with the cursor to fetch the next.
class PagedDocs {
  const PagedDocs({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> items;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;

  static const PagedDocs empty = PagedDocs(
    items: [],
    lastDoc: null,
    hasMore: false,
  );
}

/// Cross-tenant operations for the super admin dashboard.
///
/// Every method here reaches across the company boundary that the rest of the
/// app is carefully fenced inside, so all of it is gated on the caller holding
/// a `superAdmins/{uid}` doc — enforced in firestore.rules, not here. This
/// class assumes nothing about the caller; if they are not a super admin the
/// reads and writes simply fail.
class SuperAdminService {
  SuperAdminService({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  /// Resolved lazily so a subclass that overrides every method it needs can be
  /// constructed in a test without Firebase being initialised.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

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

  /// How many users are bound to [companyId], or null if the count could not be
  /// read.
  ///
  /// Users live in a root collection keyed by companyId, not a subcollection,
  /// so this is the one count the `companies/{id}/{document=**}` grant does not
  /// cover — it needs the platform-admin branch on `/users` in the rules. This
  /// used to swallow a denial and return 0, which is how a missing rule showed
  /// up as a confident, wrong "0 users" on every workspace instead of an error.
  Future<int?> userCount(String companyId) async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .count()
          .get();
      return snap.count ?? 0;
    } on FirebaseException {
      return null;
    }
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

    final usersFuture = userCount(companyId);
    final results = await Future.wait([
      countOf('products'),
      countOf('invoices'),
      countOf('salesOrders'),
      countOf('purchaseOrders'),
    ]);
    final users = await usersFuture;

    return CompanyStats(
      users: users ?? 0,
      usersUnknown: users == null,
      products: results[0],
      invoices: results[1],
      salesOrders: results[2],
      purchaseOrders: results[3],
    );
  }

  /// Expanded counts for detail view
  Future<CompanyStats> expandedCompanyStats(String companyId) async {
    Future<int> countOf(String collection) async {
      try {
        final snap = await _companies.doc(companyId).collection(collection).count().get();
        return snap.count ?? 0;
      } on FirebaseException {
        return 0;
      }
    }

    final usersFuture = userCount(companyId);
    final results = await Future.wait([
      countOf('products'),
      countOf('invoices'),
      countOf('salesOrders'),
      countOf('purchaseOrders'),
      countOf('transactions'),
      countOf('customers'),
      countOf('vendors'),
      countOf('batches'),
      countOf('returns'),
      countOf('categories'),
      countOf('roles'),
    ]);
    final users = await usersFuture;

    return CompanyStats(
      users: users ?? 0,
      usersUnknown: users == null,
      products: results[0],
      invoices: results[1],
      salesOrders: results[2],
      purchaseOrders: results[3],
      transactions: results[4],
      customers: results[5],
      vendors: results[6],
      batches: results[7],
      returns: results[8],
      categories: results[9],
      roles: results[10],
    );
  }

  Stream<List<Map<String, dynamic>>> watchCompanyUsers(String companyId) {
    return _firestore
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyProducts(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('products').orderBy('updatedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyInvoices(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('invoices').orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanySalesOrders(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('salesOrders').orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyPurchaseOrders(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('purchaseOrders').orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyTransactions(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('transactions').orderBy('date', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyAuditLogs(String companyId, {int? limit}) {
    var query = _companies.doc(companyId).collection('auditLogs').orderBy('timestamp', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> watchCompanyRoles(String companyId) {
    return _companies.doc(companyId).collection('roles').snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<Map<String, dynamic>?> getCompanySettings(String companyId) async {
    final doc = await _companies.doc(companyId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    if (data.containsKey('settings')) {
      return data['settings'] as Map<String, dynamic>;
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) {
    var query = _firestore.collection('users').orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ---------------------------------------------------------------------------
  // Paged reads
  //
  // The watch* streams above are capped at a fixed limit with no way past it,
  // which is fine for a preview but not for "read everything". These follow the
  // cursor pattern already proven in DatabaseService.getProductsPage: fetch
  // limit + 1, keep the last snapshot, derive hasMore from the overflow.
  // ---------------------------------------------------------------------------

  /// One page of a company subcollection, newest first by [orderBy].
  Future<PagedDocs> companySubcollectionPage({
    required String companyId,
    required String collection,
    required String orderBy,
    int limit = kPaginationLimit,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _companies
        .doc(companyId)
        .collection(collection)
        .orderBy(orderBy, descending: true)
        .limit(limit + 1);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return _page(await query.get(), limit);
  }

  /// One page of the root users collection, newest first.
  ///
  /// Cross-tenant, so it needs the platform-admin branch on `/users` in the
  /// rules; without it this is denied outright rather than filtered.
  Future<PagedDocs> globalUsersPage({
    int limit = kPaginationLimit,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit + 1);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return _page(await query.get(), limit);
  }

  static PagedDocs _page(QuerySnapshot<Map<String, dynamic>> snap, int limit) {
    final hasMore = snap.docs.length > limit;
    final docs = hasMore ? snap.docs.sublist(0, limit) : snap.docs;
    return PagedDocs(
      items: [
        for (final d in docs) {'id': d.id, ...d.data()},
      ],
      lastDoc: docs.isEmpty ? null : docs.last,
      hasMore: hasMore,
    );
  }

  // ---------------------------------------------------------------------------
  // Platform audit log
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _platformAuditLogs =>
      _firestore.collection('platformAuditLogs');

  Stream<List<Map<String, dynamic>>> watchPlatformAuditLogs({int limit = 200}) {
    return _platformAuditLogs
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Records what a platform admin did.
  ///
  /// Best-effort on purpose: a failure to write history must not roll back or
  /// mask the action itself, which has already landed by the time this runs.
  /// The collection is append-only in the rules, so an entry cannot later be
  /// edited away.
  Future<void> _logPlatformAction({
    required PlatformActor? actor,
    required String action,
    required String targetType,
    required String targetId,
    String? targetName,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    if (actor == null) return;
    try {
      await _platformAuditLogs.add({
        'actorUid': actor.uid,
        'actorEmail': actor.email,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'targetName': ?targetName,
        'before': ?before,
        'after': ?after,
        'timestamp': Timestamp.now(),
      });
    } on FirebaseException {
      // Swallowed deliberately — see the doc comment.
    }
  }

  /// Records the start or end of a read-only workspace inspection.
  Future<void> logInspection({
    required PlatformActor? actor,
    required String companyId,
    required String companyName,
    required bool entering,
  }) {
    return _logPlatformAction(
      actor: actor,
      action: entering ? 'inspect.enter' : 'inspect.exit',
      targetType: 'company',
      targetId: companyId,
      targetName: companyName,
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
    PlanStatus status = PlanStatus.active,
    DateTime? trialEndsAt,
    Map<String, int> limitOverrides = const {},
    String note = '',
    PlatformActor? actor,
    CompanyPlan? previous,
    String? companyName,
  }) async {
    final plan = CompanyPlan(
      planId: planId,
      status: status,
      startedAt: DateTime.now(),
      trialEndsAt: trialEndsAt,
      limitOverrides: limitOverrides,
      note: note,
    );
    await _companies.doc(companyId).update({'plan': plan.toMap()});
    await _logPlatformAction(
      actor: actor,
      action: 'plan.set',
      targetType: 'company',
      targetId: companyId,
      targetName: companyName,
      before: previous == null ? null : {'plan': previous.toMap()},
      after: {'plan': plan.toMap()},
    );
  }

  /// Suspends, reactivates, or soft-deletes a company.
  ///
  /// Suspension and soft deletion are both reversible and take effect at once:
  /// `companyActive()` in the rules stops writes as soon as this lands.
  Future<void> setStatus({
    required String companyId,
    required CompanyStatus status,
    String note = '',
    PlatformActor? actor,
    CompanyStatus? previous,
    String? companyName,
  }) async {
    await _companies.doc(companyId).update({
      'status': CompanyModel.statusToString(status),
      'statusNote': note,
      'statusChangedAt': Timestamp.now(),
    });
    await _logPlatformAction(
      actor: actor,
      action: 'status.${CompanyModel.statusToString(status)}',
      targetType: 'company',
      targetId: companyId,
      targetName: companyName,
      before: previous == null
          ? null
          : {'status': CompanyModel.statusToString(previous)},
      after: {
        'status': CompanyModel.statusToString(status),
        'statusNote': note,
      },
    );
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
    PlatformActor? actor,
    String? companyName,
  }) async {
    // Logged before the deletes, not after: a purge that dies halfway still
    // destroyed data, and an entry that only appears on success would leave the
    // most damaging possible outcome unrecorded.
    await _logPlatformAction(
      actor: actor,
      action: 'company.purge',
      targetType: 'company',
      targetId: companyId,
      targetName: companyName,
    );
    // Everything outside the company document has to go first, while the
    // company doc still exists: the join-code rules resolve through it, and
    // reading the permanent code afterwards would be impossible.
    await _releaseJoinCodes(companyId);
    await _detachMembers(companyId, onProgress: onProgress);

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

  /// Removes every join code that still resolves to [companyId].
  ///
  /// joinCodeIndex is a root collection, so a purge of the company's own
  /// subtree never touched it. A leftover entry kept handing out a dead company
  /// id to any signed-in caller who guessed the 6-character code.
  ///
  /// Both code kinds live there: the workspace's permanent code (named on the
  /// company doc) and each outstanding invite (whose document id *is* the
  /// code). The index cannot be queried by companyId — `allow list: if false` —
  /// so both are resolved by id instead.
  Future<void> _releaseJoinCodes(String companyId) async {
    final codes = <String>{};
    try {
      final company = await _companies.doc(companyId).get();
      final permanent = company.data()?['permanentJoinCode'];
      if (permanent is String && permanent.trim().isNotEmpty) {
        codes.add(permanent.trim().toUpperCase());
      }
    } catch (_) {}
    try {
      final invites =
          await _companies.doc(companyId).collection('invites').get();
      for (final doc in invites.docs) {
        codes.add(doc.id);
      }
    } catch (_) {}

    for (final code in codes) {
      try {
        await _firestore.collection('joinCodeIndex').doc(code).delete();
      } catch (_) {
        // A code already released, or one belonging to another workspace.
      }
    }
  }

  /// Detaches everyone whose user doc still points at [companyId].
  ///
  /// User docs live in the root `users` collection, so purging the company's
  /// subtree left them naming a workspace that no longer exists. Those people
  /// then signed in to a session bound to nothing: SettingsProvider found no
  /// company doc, isWorkspaceUsable defaulted to true, and they got an empty,
  /// permission-less app with no explanation. Clearing companyId instead drops
  /// them into the ordinary workspace-less state, where the app offers joining
  /// or creating one.
  Future<void> _detachMembers(
    String companyId, {
    void Function(String collection, int deleted)? onProgress,
  }) async {
    var detached = 0;
    while (true) {
      final snap = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .limit(kFirestoreBatchLimit)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'companyId': '',
          'companyName': '',
          'role': 'staff',
          'roleId': RoleModel.staffRoleId,
          'companyMemberships': _membershipsWithout(doc.data(), companyId),
        });
      }
      await batch.commit();
      detached += snap.docs.length;
      onProgress?.call('users detached', detached);
      // Updated docs drop out of the filter, so the next page starts fresh.
      if (snap.docs.length < kFirestoreBatchLimit) break;
    }
  }

  /// [data]'s companyMemberships with any entry for [companyId] removed.
  static List<Map<String, dynamic>> _membershipsWithout(
    Map<String, dynamic> data,
    String companyId,
  ) {
    final raw = data['companyMemberships'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => (m['companyId']?.toString() ?? '') != companyId)
        .toList();
  }
}
