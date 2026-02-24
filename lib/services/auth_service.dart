import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register a new admin user: creates Firebase Auth account, a company doc, and a user doc.
  Future<UserModel?> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
    required String phone,
    String role = 'admin',
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Check if this is the very first user via a metadata flag
        final configDoc = await _firestore
            .collection('metadata')
            .doc('app_config')
            .get();
        final isFirstUser = !configDoc.exists || configDoc.data()?['hasUsers'] != true;

        final assignedRole = isFirstUser ? 'superadmin' : role;
        final isApproved = isFirstUser;

        final companyDoc = await _firestore.collection('companies').add({
          'companyName': companyName,
          'phone': phone,
          'adminUid': result.user!.uid,
          'createdAt': Timestamp.now(),
        });

        final userModel = UserModel(
          uid: result.user!.uid,
          name: name,
          email: email,
          role: assignedRole,
          companyId: companyDoc.id,
          companyName: companyName,
          phone: phone,
          createdAt: DateTime.now(),
          approved: isApproved,
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toMap());

        // Mark that at least one user now exists
        if (isFirstUser) {
          await _firestore
              .collection('metadata')
              .doc('app_config')
              .set({'hasUsers': true});
        }

        return userModel;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Register a staff user under an existing company.
  /// Re-authenticates as admin afterwards since createUserWithEmailAndPassword
  /// signs in as the newly created user.
  Future<UserModel?> registerStaff({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required String companyName,
    required String adminEmail,
    required String adminPassword,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      UserModel? staffUser;
      if (result.user != null) {
        final userModel = UserModel(
          uid: result.user!.uid,
          name: name,
          email: email,
          role: 'staff',
          companyId: companyId,
          companyName: companyName,
          createdAt: DateTime.now(),
          permissions: UserModel.defaultPermissions,
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
      // If something failed after creating the staff user, still try to
      // re-authenticate as admin so the session isn't lost.
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

  Future<void> updateUserPermissions(String uid, Map<String, bool> perms) async {
    await _firestore.collection('users').doc(uid).update({'permissions': perms});
  }

  /// Get all users for a specific company.
  Stream<List<UserModel>> getAllUsers({required String companyId}) {
    return _firestore
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList());
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
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

  /// Deletes the current user's account and all associated data.
  /// Re-authenticates first, then cleans up Firestore docs, then deletes Auth account.
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

    // If admin, check if sole admin of the company and clean up company data
    if (userData.isAdmin) {
      final companyId = userData.companyId;
      final admins = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .where('role', whereIn: ['admin', 'superadmin'])
          .get();

      if (admins.docs.length <= 1) {
        // Sole admin: delete all company data
        await _deleteCompanyData(companyId);
      }
    }

    // Delete the user document
    await _firestore.collection('users').doc(user.uid).delete();

    // Delete the Firebase Auth account
    await user.delete();
  }

  /// Deletes all subcollection data for a company, then the company doc.
  Future<void> _deleteCompanyData(String companyId) async {
    final companyRef = _firestore.collection('companies').doc(companyId);

    // Delete products, categories, transactions in batches
    for (final sub in ['products', 'categories', 'transactions']) {
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

    // Delete any staff users under this company
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

    // Delete the company document itself
    await companyRef.delete();
  }

  /// Deletes a staff user's Firestore doc (admin only).
  /// The staff's Firebase Auth account remains but login will fail
  /// because the app requires a Firestore user doc.
  Future<void> deleteStaffUser(String staffUid) async {
    await _firestore.collection('users').doc(staffUid).delete();
  }

  /// Stream of users awaiting approval (approved == false).
  Stream<List<UserModel>> getPendingUsers() {
    return _firestore
        .collection('users')
        .where('approved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList());
  }

  /// Approve a pending user by setting approved = true.
  Future<void> approveUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({'approved': true});
  }

  /// Reject a pending user: delete user doc and their company doc.
  Future<void> rejectUser(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId != null && companyId.isNotEmpty) {
        await _firestore.collection('companies').doc(companyId).delete();
      }
    }
    await _firestore.collection('users').doc(uid).delete();
  }

  Future<void> logout() async {
    await _auth.signOut();
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
