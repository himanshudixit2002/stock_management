import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../utils/error_helpers.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  Future<void> initialize() async {
    final firebaseUser = _authService.currentUser;
    if (firebaseUser != null) {
      try {
        _currentUser = await _authService.getUserData(firebaseUser.uid);
      } catch (e) {
        _currentUser = null;
        _errorMessage = friendlyError(e, fallback: 'Could not load account data.');
      }
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
    required String phone,
    String role = 'admin',
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
        role: role,
      );
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

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.login(
        email: email,
        password: password,
      );

      if (_currentUser == null) {
        await _authService.logout();
        _errorMessage = 'Account data not found. Please contact your administrator.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

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

  Future<bool> changePassword(String currentPassword, String newPassword) async {
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
    await _authService.logout();
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Stream<List<UserModel>> getAllUsers() {
    final companyId = _currentUser?.companyId ?? '';
    return _authService.getAllUsers(companyId: companyId);
  }

  Future<void> updateUserRole(String uid, String newRole) async {
    try {
      await _authService.updateUserRole(uid, newRole);
    } catch (e) {
      _errorMessage = friendlyError(e);
      notifyListeners();
    }
  }

  Future<bool> updateStaffPermissions(String uid, Map<String, bool> perms) async {
    try {
      await _authService.updateUserPermissions(uid, perms);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
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
    try {
      await _authService.deleteStaffUser(staffUid);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> addStaffUser({
    required String name,
    required String email,
    required String password,
    required String adminPassword,
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
      );

      // Re-fetch admin user data (we're signed back in as admin)
      final currentFirebaseUser = _authService.currentUser;
      if (currentFirebaseUser != null) {
        _currentUser = await _authService.getUserData(currentFirebaseUser.uid);
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
}
