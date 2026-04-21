import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
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
    final companyId = _currentUser?.companyId ?? '';
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
      await _authService.deleteStaffUser(staffUid);
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
      notifyListeners();
      return false;
    }
  }

  /// Ensure roles exist and migrate legacy user if needed.
  Future<void> ensureRbacReady() async {
    if (_currentUser == null) return;
    final companyId = _currentUser!.companyId;
    await _authService.ensureRolesSeeded(companyId);
    if (_currentUser!.roleId.isEmpty) {
      await _authService.migrateUserToRbac(_currentUser!.uid, companyId);
      await refreshCurrentUser();
    }
  }
}
