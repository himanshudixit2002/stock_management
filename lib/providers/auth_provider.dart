import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config/permissions.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../providers/role_provider.dart';
import '../utils/error_helpers.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _sessionExpired = false;

  RoleProvider? _roleProvider;
  StreamSubscription<User?>? _authStateSub;

  /// A stand-in user used while a platform admin inspects a workspace.
  ///
  /// Null in every ordinary session.
  UserModel? _inspectionUser;

  /// The user the rest of the app should behave as.
  ///
  /// During a workspace inspection this is a synthetic, view-only user bound to
  /// the inspected workspace, so every screen loads that tenant's data with its
  /// mutating controls gated off. [signedInUser] remains the real account.
  UserModel? get currentUser => _inspectionUser ?? _currentUser;

  /// The account actually signed in, ignoring any inspection override.
  UserModel? get signedInUser => _currentUser;

  bool get isInspecting => _inspectionUser != null;

  /// Rebinds this session to [companyId] as a read-only observer.
  void beginInspection({
    required String companyId,
    required String companyName,
  }) {
    final real = _currentUser;
    if (real == null) return;
    _inspectionUser =
        real.copyWith(
            companyId: companyId,
            companyName: companyName,
            // Not 'admin'/'owner': UserModel.effectivePermissions short-circuits
            // to allTrue() for those, which would hand the inspector every
            // write control in the UI.
            role: 'viewer',
            roleId: '',
            permissions: AppPermissions.viewOnly(),
          )
          // Set directly so a later role-stream emission cannot resolve this
          // synthetic user against the inspected tenant's role documents.
          ..resolvedPermissions = AppPermissions.viewOnly();
    notifyListeners();
  }

  void endInspection() {
    if (_inspectionUser == null) return;
    _inspectionUser = null;
    notifyListeners();
  }

  /// Drops any inspection override without notifying.
  ///
  /// For teardown paths (logout, session expiry, account deletion) that clear
  /// [_currentUser] and notify once themselves. Inspection used to be cleared
  /// *only* by the banner's "Return to console" button, so signing out mid-
  /// inspection left [_inspectionUser] set: [currentUser] then still returned a
  /// synthetic user carrying the inspected tenant's companyId and the previous
  /// admin's uid, and the next person to sign in on this instance had every
  /// provider bound to a workspace they had never touched.
  void _clearInspection() {
    _inspectionUser = null;
  }

  /// True (with an error surfaced) when a mutation was attempted mid-inspection.
  ///
  /// Guards the calls that take their target workspace from the *real* account
  /// while the rest of the app is bound to the inspected one — acting on them
  /// would quietly change the inspector's own workspace.
  bool _refuseWhileInspecting() {
    if (!isInspecting) return false;
    _errorMessage =
        'You are inspecting another workspace. Return to the console first.';
    notifyListeners();
    return true;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  // Follows [currentUser], not the real account: during an inspection the
  // synthetic user is a 'viewer', and reporting isAdmin from the real admin
  // account left admin-only controls on screen throughout a session the banner
  // was calling view-only.
  bool get isAdmin => currentUser?.isAdmin ?? false;
  bool get sessionExpired => _sessionExpired;

  /// Re-resolve when the roles stream emits (roles load after first frame).
  void _onRoleProviderChanged() {
    _resolveUserPermissions();
    notifyListeners();
  }

  /// Attach the RoleProvider so resolved permissions can be computed.
  void attachRoleProvider(RoleProvider roleProvider) {
    _roleProvider?.removeListener(_onRoleProviderChanged);
    _roleProvider = roleProvider;
    _roleProvider!.addListener(_onRoleProviderChanged);
    _resolveUserPermissions();
    notifyListeners();
  }

  void detachRoleProvider() {
    _roleProvider?.removeListener(_onRoleProviderChanged);
    _roleProvider = null;
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    detachRoleProvider();
    super.dispose();
  }

  void _resolveUserPermissions() {
    if (_currentUser == null || _roleProvider == null) return;
    final roleId = _currentUser!.roleId;
    if (roleId.isEmpty) {
      // Legacy user — do not keep RBAC overlay from a previous workspace
      _currentUser!.resolvedPermissions = null;
      return;
    }
    _currentUser!.resolvedPermissions = _roleProvider!.resolvePermissions(
      roleId: roleId,
      overrides: _currentUser!.permissions,
    );
  }

  Future<void> initialize() async {
    _errorMessage = null;
    _sessionExpired = false;
    final firebaseUser = _authService.currentUser;
    if (firebaseUser != null) {
      try {
        _currentUser = await _authService.getUserData(firebaseUser.uid);
        _resolveUserPermissions();
      } catch (e) {
        _currentUser = null;
        _errorMessage = friendlyError(
          e,
          fallback: 'Could not load account data.',
        );
      }
      notifyListeners();
    }
    _listenAuthState();
  }

  void _listenAuthState() {
    _authStateSub?.cancel();
    _authStateSub = _authService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null && _currentUser != null) {
        _sessionExpired = true;
        detachRoleProvider();
        _clearInspection();
        _currentUser = null;
        notifyListeners();
      } else if (firebaseUser != null && _currentUser == null && !_isLoading) {
        try {
          _currentUser = await _authService.getUserData(firebaseUser.uid);
          _resolveUserPermissions();
          notifyListeners();
        } catch (_) {}
      }
    });
  }

  Future<void> refreshCurrentUser() async {
    _errorMessage = null;
    final firebaseUser = _authService.currentUser;
    if (firebaseUser != null) {
      try {
        _currentUser = await _authService.getUserData(firebaseUser.uid);
        _resolveUserPermissions();
        notifyListeners();
      } catch (e) {
        _errorMessage = friendlyError(
          e,
          fallback: 'Could not refresh account data.',
        );
        notifyListeners();
      }
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
    required String phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.register(
        name: name,
        email: email,
        password: password,
        companyName: companyName,
        phone: phone,
      );
      _resolveUserPermissions();
      _isLoading = false;
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.login(email: email, password: password);

      if (_currentUser == null) {
        await _authService.logout();
        _errorMessage =
            'Account data not found. Please contact your administrator.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _resolveUserPermissions();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.resetPassword(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.changePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _errorMessage = null;
    _sessionExpired = false;
    try {
      await _authService.logout();
    } catch (e) {
      _errorMessage = e.toString();
    }
    detachRoleProvider();
    _clearInspection();
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearSessionExpired() {
    _sessionExpired = false;
  }

  Stream<List<UserModel>> getAllUsers() {
    // [currentUser], so User Management lists the workspace the rest of the app
    // is bound to. Reading the real account here meant that while inspecting
    // tenant B — banner, providers and all — this screen streamed tenant A's
    // users.
    final companyId = currentUser?.companyId ?? '';
    return _authService.getAllUsers(companyId: companyId);
  }

  Future<void> updateUserRole(String uid, String newRole) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.updateUserRole(uid, newRole);
    } catch (e) {
      _errorMessage = friendlyError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateUserRoleId(String uid, String roleId) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.updateUserRoleAssignment(uid, roleId);
    } catch (e) {
      _errorMessage = friendlyError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateStaffPermissions(
    String uid,
    Map<String, bool> perms,
  ) async {
    if (_isLoading) return false;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.updateUserPermissions(uid, perms);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({String? name, String? phone}) async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.updateProfile(
        uid: _currentUser!.uid,
        name: name,
        phone: phone,
      );
      _currentUser = _currentUser!.copyWith(
        name: name ?? _currentUser!.name,
        phone: phone ?? _currentUser!.phone,
      );
      _resolveUserPermissions();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteAccount(String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.deleteAccount(password);
      detachRoleProvider();
      _clearInspection();
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteStaffUser(String staffUid) async {
    if (_isLoading) return false;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.deleteStaffUser(
        staffUid,
        // The workspace on screen, so removing someone while inspecting revokes
        // them from the tenant being looked at rather than the inspector's own.
        companyId: currentUser?.companyId ?? '',
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<CompanyMembership?> createNewCompany(String companyName) async {
    if (_currentUser == null) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final membership = await _authService.createNewCompany(
        uid: _currentUser!.uid,
        companyName: companyName,
      );
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return membership;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> switchCompany(CompanyMembership membership) async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.switchCompany(
        uid: _currentUser!.uid,
        companyId: membership.companyId,
        companyName: membership.companyName,
        role: membership.role,
        roleId: membership.roleId,
      );
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> generateInviteCode() async {
    if (_currentUser == null) return null;
    // Targets the real account's workspace, so during an inspection this would
    // mint a code for the inspector's own company while the UI showed someone
    // else's. Inspection is read-only; refuse rather than act on the wrong one.
    if (_refuseWhileInspecting()) return null;
    try {
      return await _authService.generateInviteCode(
        companyId: _currentUser!.companyId,
        companyName: _currentUser!.companyName,
      );
    } catch (e) {
      _errorMessage = friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  /// Backfill permanent join code for a workspace (creator only).
  Future<String?> ensurePermanentJoinCodeForCompany(String companyId) async {
    if (_currentUser == null) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final code = await _authService.ensurePermanentJoinCodeForCompany(
        companyId: companyId,
        uid: _currentUser!.uid,
      );
      _isLoading = false;
      notifyListeners();
      return code;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<String?> regeneratePermanentJoinCode() async {
    if (_currentUser == null) return null;
    if (_refuseWhileInspecting()) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final code = await _authService.regeneratePermanentJoinCode(
        companyId: _currentUser!.companyId,
        companyName: _currentUser!.companyName,
      );
      _isLoading = false;
      notifyListeners();
      return code;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, String>> getPermanentJoinCodesForSwitcher(
    Iterable<String> companyIds,
  ) {
    return _authService.getPermanentJoinCodesForCompanies(companyIds);
  }

  Future<({Map<String, String> joinCodes, Set<String> creatorCompanyIds})>
  getCompanySwitcherMeta(Iterable<String> companyIds) {
    return _authService.getCompanySwitcherMeta(
      companyIds,
      _currentUser?.uid ?? '',
    );
  }

  Future<bool> joinCompany(String inviteCode) async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.joinCompany(
        uid: _currentUser!.uid,
        inviteCode: inviteCode,
      );
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> leaveCompany(CompanyMembership membership) async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.leaveCompany(
        uid: _currentUser!.uid,
        membership: membership,
      );
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> addStaffUser({
    required String name,
    required String email,
    required String password,
    required String adminPassword,
    String roleId = '',
  }) async {
    if (_refuseWhileInspecting()) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final companyId = _currentUser?.companyId ?? '';
      final companyName = _currentUser?.companyName ?? '';
      final adminEmail = _currentUser?.email ?? '';

      final newUser = await _authService.registerStaff(
        name: name,
        email: email,
        password: password,
        companyId: companyId,
        companyName: companyName,
        adminEmail: adminEmail,
        adminPassword: adminPassword,
        roleId: roleId,
      );

      final currentFirebaseUser = _authService.currentUser;
      if (currentFirebaseUser != null) {
        _currentUser = await _authService.getUserData(currentFirebaseUser.uid);
        _resolveUserPermissions();
      }

      _isLoading = false;
      notifyListeners();
      return newUser != null;
    } catch (e) {
      _errorMessage = AuthService.getErrorMessage(e);
      _isLoading = false;
      await _abandonSessionIfNotAdmin();
      notifyListeners();
      return false;
    }
  }

  /// Signs out when the Firebase session no longer matches [_currentUser].
  ///
  /// createUserWithEmailAndPassword leaves the *new* account signed in, and
  /// registerStaff signs back in as the admin to undo that. If the admin
  /// mistyped their password both attempts fail and we land here still
  /// authenticated as the freshly created staff user while [_currentUser] holds
  /// the admin. The auth listener does not correct it (it only fires when
  /// _currentUser is null), so the UI kept rendering admin identity and
  /// permissions over a session that had neither — and every Firestore read
  /// silently denied, because that account has no user doc yet.
  Future<void> _abandonSessionIfNotAdmin() async {
    final signedIn = _authService.currentUser;
    if (_currentUser == null) return;
    if (signedIn != null && signedIn.uid == _currentUser!.uid) return;
    try {
      await _authService.logout();
    } catch (_) {}
    detachRoleProvider();
    _clearInspection();
    _currentUser = null;
    _sessionExpired = true;
    _errorMessage =
        'Your admin password was not accepted, so the session was ended for '
        'safety. Sign in again — the new staff account may need to be removed.';
  }

  /// Ensure roles exist and migrate legacy user if needed.
  ///
  /// No-op while inspecting: this seeds role documents, and app.dart calls it
  /// during the inspection bind. Keyed off the real account it wrote into the
  /// *inspector's* workspace instead of the one on screen; keyed off the
  /// inspected one it would be a write from a session that is meant to be
  /// read-only. Neither is wanted, and a workspace being inspected has been
  /// used already, so its roles are already seeded.
  Future<void> ensureRbacReady() async {
    if (_currentUser == null || isInspecting) return;
    final companyId = _currentUser!.companyId;
    if (companyId.isEmpty) return;
    // Best-effort throughout. app.dart calls this during provider start-up
    // inside a try/catch that renders a permanent "Could Not Load Data" screen,
    // so anything that throws here takes the whole session down. Both steps are
    // conveniences — seeding roles that an established workspace already has,
    // and backfilling a legacy roleId — and a member without the rights to
    // perform either still has a perfectly usable session.
    try {
      await _authService.ensureRolesSeeded(companyId);
    } catch (_) {}
    if (_currentUser!.roleId.isEmpty) {
      try {
        await _authService.migrateUserToRbac(_currentUser!.uid, companyId);
        await refreshCurrentUser();
      } catch (_) {}
    }
  }
}
