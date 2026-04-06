import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/role_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _joinCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  User? get currentUser => _auth.currentUser;

  String _randomJoinCode() {
    final rng = Random.secure();
    return List.generate(
      6,
      (_) => _joinCodeChars[rng.nextInt(_joinCodeChars.length)],
    ).join();
  }

  /// Allocates [joinCodeIndex] doc and sets [permanentJoinCode] on the company.
  Future<String> _allocatePermanentJoinCode(
    String companyId,
    String companyName,
  ) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final code = _randomJoinCode();
      final indexRef = _firestore.collection('joinCodeIndex').doc(code);
      try {
        await _firestore.runTransaction((txn) async {
          final snap = await txn.get(indexRef);
          if (snap.exists) {
            throw StateError('collision');
          }
          txn.set(indexRef, {
            'companyId': companyId,
            'companyName': companyName,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        if (e is StateError && e.message == 'collision') {
          continue;
        }
        continue;
      }
      try {
        await _firestore.collection('companies').doc(companyId).update({
          'permanentJoinCode': code,
        });
        return code;
      } catch (e) {
        try {
          await indexRef.delete();
        } catch (_) {}
        rethrow;
      }
    }
    throw Exception('Could not allocate a unique company join code. Try again.');
  }

  /// Ensures the company has a permanent join code (for existing tenants). Creator only.
  Future<String?> ensurePermanentJoinCodeForCompany({
    required String companyId,
    required String uid,
  }) async {
    final companyRef = _firestore.collection('companies').doc(companyId);
    final snap = await companyRef.get();
    if (!snap.exists) return null;
    final data = snap.data()!;
    final existing = (data['permanentJoinCode'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final adminUid = data['adminUid'] as String? ?? '';
    if (adminUid != uid) {
      throw Exception('Only the company creator can generate the first join code.');
    }
    final name = (data['companyName'] as String?)?.trim() ?? '';
    return _allocatePermanentJoinCode(companyId, name);
  }

  /// Regenerates permanent code (invalidates old index entry). Admin only on client.
  Future<String> regeneratePermanentJoinCode({
    required String companyId,
    required String companyName,
  }) async {
    final companyRef = _firestore.collection('companies').doc(companyId);
    final snap = await companyRef.get();
    if (!snap.exists) throw Exception('Company not found');
    final old = (snap.data()!['permanentJoinCode'] as String?)?.trim() ?? '';
    if (old.isNotEmpty) {
      await _firestore.collection('joinCodeIndex').doc(old).delete();
    }
    await companyRef.update({'permanentJoinCode': FieldValue.delete()});
    return _allocatePermanentJoinCode(companyId, companyName);
  }

  /// Fetches [permanentJoinCode] from company docs the user may need for the switcher UI.
  Future<Map<String, String>> getPermanentJoinCodesForCompanies(
    Iterable<String> companyIds,
  ) async {
    final meta = await getCompanySwitcherMeta(companyIds, '');
    return meta.joinCodes;
  }

  /// Join codes + which companies the user created (for generating first code / regenerate UX).
  Future<({Map<String, String> joinCodes, Set<String> creatorCompanyIds})>
      getCompanySwitcherMeta(
    Iterable<String> companyIds,
    String uid,
  ) async {
    final joinCodes = <String, String>{};
    final creatorCompanyIds = <String>{};
    for (final id in companyIds.toSet()) {
      if (id.isEmpty) continue;
      final doc = await _firestore.collection('companies').doc(id).get();
      if (!doc.exists) continue;
      final data = doc.data()!;
      final code = (data['permanentJoinCode'] as String?)?.trim() ?? '';
      if (code.isNotEmpty) joinCodes[id] = code;
      if (uid.isNotEmpty && (data['adminUid'] as String? ?? '') == uid) {
        creatorCompanyIds.add(id);
      }
    }
    return (joinCodes: joinCodes, creatorCompanyIds: creatorCompanyIds);
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register a new admin user: creates Firebase Auth account, a company doc,
  /// seeds default roles, and creates a user doc with the Owner role.
  Future<UserModel?> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
    required String phone,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        final companyDoc = await _firestore.collection('companies').add({
          'companyName': companyName,
          'phone': phone,
          'adminUid': result.user!.uid,
          'createdAt': Timestamp.now(),
        });

        await _allocatePermanentJoinCode(companyDoc.id, companyName);

        final membership = CompanyMembership(
          companyId: companyDoc.id,
          companyName: companyName,
          role: 'admin',
          roleId: RoleModel.ownerRoleId,
        );

        final userModel = UserModel(
          uid: result.user!.uid,
          name: name,
          email: email,
          role: 'admin',
          roleId: RoleModel.ownerRoleId,
          companyId: companyDoc.id,
          companyName: companyName,
          phone: phone,
          createdAt: DateTime.now(),
          companyMemberships: [membership],
        );

        // Create user doc first so Firestore rules can verify membership
        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toMap());

        await _seedDefaultRoles(companyDoc.id);

        return userModel;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Register a staff user under an existing company.
  Future<UserModel?> registerStaff({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required String companyName,
    required String adminEmail,
    required String adminPassword,
    String roleId = '',
  }) async {
    try {
      final effectiveRoleId = roleId.isEmpty ? RoleModel.staffRoleId : roleId;

      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      UserModel? staffUser;
      if (result.user != null) {
        final roleField = RoleModel.userRoleFieldForRoleId(effectiveRoleId);
        final membership = CompanyMembership(
          companyId: companyId,
          companyName: companyName,
          role: roleField,
          roleId: effectiveRoleId,
        );

        final userModel = UserModel(
          uid: result.user!.uid,
          name: name,
          email: email,
          role: roleField,
          roleId: effectiveRoleId,
          companyId: companyId,
          companyName: companyName,
          createdAt: DateTime.now(),
          permissions: const {},
          companyMemberships: [membership],
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toMap());

        staffUser = userModel;
      }

      await _auth.signInWithEmailAndPassword(
        email: adminEmail,
        password: adminPassword,
      );

      return staffUser;
    } catch (e) {
      try {
        await _auth.signInWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<UserModel?> login({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        return await getUserData(result.user!.uid);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUserRole(String uid, String newRole) async {
    await _firestore.collection('users').doc(uid).update({'role': newRole});
  }

  /// Updates `roleId`, derived `role`, and matching `companyMemberships` entry.
  Future<void> updateUserRoleAssignment(String uid, String roleId) async {
    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final roleField = RoleModel.userRoleFieldForRoleId(roleId);
    final activeCompanyId = data['companyId'] as String? ?? '';

    final rawList = data['companyMemberships'];
    final List<Map<String, dynamic>> updatedMemberships = [];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        if (m['companyId']?.toString() == activeCompanyId) {
          m['role'] = roleField;
          m['roleId'] = roleId;
        }
        updatedMemberships.add(m);
      }
    }

    final update = <String, dynamic>{
      'role': roleField,
      'roleId': roleId,
    };
    if (updatedMemberships.isNotEmpty) {
      update['companyMemberships'] = updatedMemberships;
    }
    await ref.update(update);
  }

  Future<void> updateUserPermissions(
    String uid,
    Map<String, bool> perms,
  ) async {
    await _firestore.collection('users').doc(uid).update({
      'permissions': perms,
    });
  }

  Stream<List<UserModel>> getAllUsers({required String companyId}) {
    return _firestore
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserModel.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No user is currently signed in.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProfile({
    required String uid,
    String? name,
    String? phone,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (updates.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(updates);
    }
  }

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No user is currently signed in.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    final userData = await getUserData(user.uid);
    if (userData == null) {
      throw Exception('User data not found.');
    }

    if (userData.isAdmin) {
      final companyId = userData.companyId;
      final admins = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .where('role', isEqualTo: 'admin')
          .get();

      if (admins.docs.length <= 1) {
        await _deleteCompanyData(companyId);
      }
    }

    await _firestore.collection('users').doc(user.uid).delete();
    await user.delete();
  }

  Future<void> _deleteCompanyData(String companyId) async {
    final companyRef = _firestore.collection('companies').doc(companyId);
    final companySnap = await companyRef.get();
    if (companySnap.exists) {
      final code = (companySnap.data()?['permanentJoinCode'] as String?)?.trim() ??
          '';
      if (code.isNotEmpty) {
        await _firestore.collection('joinCodeIndex').doc(code).delete();
      }
    }

    for (final sub in [
      'products', 'categories', 'transactions', 'vendors', 'roles',
      'purchaseOrders', 'salesOrders', 'returns', 'customers', 'batches',
      'stockTakes', 'auditLogs', 'notifications', 'priceHistory',
      'warehouseZones', 'invoices', 'invites',
    ]) {
      QuerySnapshot snapshot;
      do {
        snapshot = await companyRef.collection(sub).limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (snapshot.docs.length == 400);
    }

    final staffDocs = await _firestore
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .get();
    if (staffDocs.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in staffDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await companyRef.delete();
  }

  Future<void> deleteStaffUser(String staffUid) async {
    await _firestore.collection('users').doc(staffUid).delete();
  }

  Future<CompanyMembership> createNewCompany({
    required String uid,
    required String companyName,
  }) async {
    final companyDoc = await _firestore.collection('companies').add({
      'companyName': companyName,
      'adminUid': uid,
      'createdAt': Timestamp.now(),
    });

    await _seedDefaultRoles(companyDoc.id);
    await _allocatePermanentJoinCode(companyDoc.id, companyName);

    final membership = CompanyMembership(
      companyId: companyDoc.id,
      companyName: companyName,
      role: 'admin',
      roleId: RoleModel.ownerRoleId,
    );

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    final existing = (data['companyMemberships'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (existing.isEmpty) {
      final currentId = (data['companyId'] ?? '') as String;
      final currentName = (data['companyName'] ?? '') as String;
      final currentRole = (data['role'] ?? 'admin') as String;
      final currentRoleId = (data['roleId'] ?? '') as String;
      final currentMembership = CompanyMembership(
        companyId: currentId,
        companyName: currentName,
        role: currentRole,
        roleId: currentRoleId,
      );
      await _firestore.collection('users').doc(uid).update({
        'companyMemberships': [currentMembership.toMap(), membership.toMap()],
        'companyId': companyDoc.id,
        'companyName': companyName,
        'role': 'admin',
        'roleId': RoleModel.ownerRoleId,
      });
    } else {
      await _firestore.collection('users').doc(uid).update({
        'companyMemberships': FieldValue.arrayUnion([membership.toMap()]),
        'companyId': companyDoc.id,
        'companyName': companyName,
        'role': 'admin',
        'roleId': RoleModel.ownerRoleId,
      });
    }

    return membership;
  }

  Future<void> switchCompany({
    required String uid,
    required String companyId,
    required String companyName,
    required String role,
    String roleId = '',
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'companyId': companyId,
      'companyName': companyName,
      'role': role,
      'roleId': roleId,
    });
  }

  Future<String> generateInviteCode({
    required String companyId,
    required String companyName,
  }) async {
    final rng = Random.secure();
    final code = List.generate(
      6,
      (_) => _joinCodeChars[rng.nextInt(_joinCodeChars.length)],
    ).join();

    await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('invites')
        .doc(code)
        .set({
      'code': code,
      'companyId': companyId,
      'companyName': companyName,
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7))),
    });

    return code;
  }

  Future<CompanyMembership> joinCompany({
    required String uid,
    required String inviteCode,
  }) async {
    final normalized = inviteCode.trim().toUpperCase();
    if (normalized.length < 6) {
      throw Exception('Enter a 6-character code.');
    }

    String companyId;
    String companyName;

    final inviteQuery = await _firestore
        .collectionGroup('invites')
        .where('code', isEqualTo: normalized)
        .limit(1)
        .get();

    if (inviteQuery.docs.isNotEmpty) {
      final invite = inviteQuery.docs.first.data();
      final expiresAt = (invite['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        throw Exception(
          'This invite code has expired. Ask the admin for a new one.',
        );
      }
      companyId = invite['companyId'] as String;
      companyName = invite['companyName'] as String? ?? '';
    } else {
      final indexSnap =
          await _firestore.collection('joinCodeIndex').doc(normalized).get();
      if (!indexSnap.exists) {
        throw Exception('Invalid code. Use the company join code or a fresh invite.');
      }
      final idx = indexSnap.data()!;
      companyId = idx['companyId'] as String;
      companyName = idx['companyName'] as String? ?? '';
      final co =
          await _firestore.collection('companies').doc(companyId).get();
      if (!co.exists) {
        throw Exception('This company no longer exists.');
      }
      final onCompany =
          (co.data()?['permanentJoinCode'] as String?)?.trim().toUpperCase() ??
              '';
      if (onCompany != normalized) {
        throw Exception('This join code is no longer valid. Ask for the current code.');
      }
    }

    final membership = CompanyMembership(
      companyId: companyId,
      companyName: companyName,
      role: 'staff',
      roleId: RoleModel.staffRoleId,
    );

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final data = userDoc.data() ?? {};
    final existing = (data['companyMemberships'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (existing.isEmpty) {
      final currentId = (data['companyId'] ?? '') as String;
      final currentName = (data['companyName'] ?? '') as String;
      final currentRole = (data['role'] ?? 'admin') as String;
      final currentRoleId = (data['roleId'] ?? '') as String;
      final currentMembership = CompanyMembership(
        companyId: currentId,
        companyName: currentName,
        role: currentRole,
        roleId: currentRoleId,
      );
      await _firestore.collection('users').doc(uid).update({
        'companyMemberships': [currentMembership.toMap(), membership.toMap()],
        'companyId': companyId,
        'companyName': companyName,
        'role': membership.role,
        'roleId': membership.roleId,
      });
    } else {
      await _firestore.collection('users').doc(uid).update({
        'companyMemberships': FieldValue.arrayUnion([membership.toMap()]),
        'companyId': companyId,
        'companyName': companyName,
        'role': membership.role,
        'roleId': membership.roleId,
      });
    }

    return membership;
  }

  Future<void> leaveCompany({
    required String uid,
    required CompanyMembership membership,
  }) async {
    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final activeCompanyId = (data['companyId'] ?? '') as String;
    final rawList = data['companyMemberships'];
    final list = <Map<String, dynamic>>[];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }

    Map<String, dynamic>? storedEntry;
    for (final m in list) {
      if ((m['companyId']?.toString() ?? '') == membership.companyId) {
        storedEntry = m;
        break;
      }
    }

    if (storedEntry == null) {
      if (list.isEmpty &&
          activeCompanyId.isNotEmpty &&
          activeCompanyId == membership.companyId) {
        await ref.update({
          'companyMemberships': <Map<String, dynamic>>[],
          'companyId': '',
          'companyName': '',
          'role': 'staff',
          'roleId': RoleModel.staffRoleId,
        });
        return;
      }
      throw Exception('You are not a member of this company.');
    }

    final remaining = List<Map<String, dynamic>>.from(list);
    final removeIdx =
        remaining.indexWhere((m) => identical(m, storedEntry));
    if (removeIdx >= 0) remaining.removeAt(removeIdx);

    final updates = <String, dynamic>{
      'companyMemberships': FieldValue.arrayRemove([storedEntry]),
    };

    if (activeCompanyId == membership.companyId) {
      if (remaining.isNotEmpty) {
        final next = remaining.first;
        updates['companyId'] = next['companyId'] ?? '';
        updates['companyName'] = next['companyName'] ?? '';
        updates['role'] = next['role'] ?? 'staff';
        updates['roleId'] = next['roleId'] ?? '';
      } else {
        updates['companyId'] = '';
        updates['companyName'] = '';
        updates['role'] = 'staff';
        updates['roleId'] = RoleModel.staffRoleId;
      }
    }

    await ref.update(updates);
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  /// Seed default system roles into a company's roles sub-collection.
  Future<void> _seedDefaultRoles(String companyId) async {
    final batch = _firestore.batch();
    for (final role in RoleModel.defaultRoles(companyId)) {
      final ref = _firestore
          .collection('companies')
          .doc(companyId)
          .collection('roles')
          .doc(role.id);
      batch.set(ref, role.toMap());
    }
    await batch.commit();
  }

  /// Seed default roles for an existing company if they don't exist yet.
  Future<void> ensureRolesSeeded(String companyId) async {
    final snapshot = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('roles')
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      await _seedDefaultRoles(companyId);
    }
  }

  /// Migrate a legacy user (no roleId) to the new RBAC system.
  Future<void> migrateUserToRbac(String uid, String companyId) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;

    final currentRoleId = safeStringOrNull(data['roleId']);
    if (currentRoleId != null && currentRoleId.isNotEmpty) return;

    final role = (data['role'] ?? 'staff') as String;
    final String newRoleId;
    switch (role) {
      case 'admin':
        newRoleId = RoleModel.ownerRoleId;
      case 'manager':
        newRoleId = RoleModel.managerRoleId;
      case 'viewer':
        newRoleId = RoleModel.viewerRoleId;
      default:
        newRoleId = RoleModel.staffRoleId;
    }

    await _firestore.collection('users').doc(uid).update({
      'roleId': newRoleId,
    });
  }

  static String? safeStringOrNull(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    return v.toString();
  }

  static String getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'weak-password':
          return 'The password is too weak. Please use at least 6 characters.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'invalid-credential':
          return 'Invalid email or password. Please try again.';
        default:
          return 'An error occurred. Please try again.';
      }
    }
    return error.toString();
  }
}
