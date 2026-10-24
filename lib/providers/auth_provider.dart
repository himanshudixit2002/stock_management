import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config/permissions.dart';
import '../models/user_model.dart';
import '../models/workspace_member_model.dart';
import '../services/auth_service.dart';
import '../services/membership_access.dart';
import '../providers/role_provider.dart';
import '../utils/error_helpers.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _sessionExpired = false;

  /// True while [logout] or [deleteAccount] runs. Firebase may report the
  /// sign-out before they have cleared the user, and the auth listener then
  /// took the user's own sign-out for an expired session.
  bool _signingOut = false;

  RoleProvider? _roleProvider;
  StreamSubscription<User?>? _authStateSub;

  /// Live view of the signed-in account's own user doc. See [_watchUserDoc].
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  String? _userDocSubUid;
  int _userDocWatchFailures = 0;

  /// Why the session just lost access, for the UI to tell the user.
  String? _accessNotice;
  int _accessNoticeEpoch = 0;

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

  /// Set when the session loses access underneath the user: an admin removed
  /// them from the workspace they were using, or their account record is gone.
  /// The app shell shows it; [accessNoticeEpoch] changes each time a new one is
  /// raised, so the shell can react once per notice.
  String? get accessNotice => _accessNotice;
  int get accessNoticeEpoch => _accessNoticeEpoch;

  /// Drops the notice once it has been shown. Does not notify: nothing needs to
  /// rebuild because a message was read.
  void clearAccessNotice() {
    _accessNotice = null;
  }

  void _raiseAccessNotice(String message) {
    _accessNotice = message;
    _accessNoticeEpoch++;
  }

  static String _lostAccessNotice(String companyName) => companyName.isEmpty
      ? 'You no longer have access to your workspace.'
      : 'You no longer have access to $companyName.';

  static String _removedByAdminNotice(String companyName) =>
      companyName.isEmpty
      ? 'An admin removed you from your workspace.'
      : 'An admin removed you from $companyName.';

  static const String _noAccountRecordNotice =
      'This account is no longer part of any workspace. If an admin removed '
      'you, ask them for a new invite.';

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
    _stopWatchingUserDoc();
    detachRoleProvider();
    super.dispose();
  }

  /// Watches the signed-in account's own user doc for as long as it is signed
  /// in.
  ///
  /// Nothing watched it before, so a person an admin removed kept their whole
  /// session. The rules refused every new read and write, but the app stayed
  /// on Home showing permission errors until it was restarted. Now a removal
  /// lands within moments. The account is detached from the workspace (see
  /// MembershipAccess.detachFields), the shell drops it into the workspace-less
  /// screen with an explanation, and an account whose doc was deleted outright
  /// (by an older build) is signed out with one.
  ///
  /// Other server-side changes are adopted too, such as a role or permission
  /// an admin changed, or a switch made on another device. The rules already
  /// apply those to every request, so the session catching up keeps what the
  /// app shows in line with what it is allowed to do.
  void _watchUserDoc() {
    final uid = _currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _stopWatchingUserDoc();
      return;
    }
    if (_userDocSub != null && _userDocSubUid == uid) return;
    _stopWatchingUserDoc();
    _userDocSubUid = uid;
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub;
    sub = _authService.watchUserDoc(uid).listen(
      (snap) {
        _userDocWatchFailures = 0;
        _onUserDocSnapshot(snap);
      },
      // Firestore closes a listener that errors. The usual cause is the session
      // briefly belonging to another account (adding staff signs in as the new
      // account and back), which is not a removal. Forget this one. The auth
      // listener starts a fresh one when the session is back on this account,
      // or, if it already is, a retry below does.
      onError: (Object _) {
        if (!identical(_userDocSub, sub)) return;
        _userDocSub = null;
        _userDocSubUid = null;
        if (++_userDocWatchFailures > 5) return;
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (_userDocSub == null &&
              _currentUser?.uid == uid &&
              _authService.currentUser?.uid == uid) {
            _watchUserDoc();
          }
        });
      },
    );
    _userDocSub = sub;
  }

  void _stopWatchingUserDoc() {
    _userDocSub?.cancel();
    _userDocSub = null;
    _userDocSubUid = null;
  }

  void _onUserDocSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final before = _currentUser;
    if (before == null || snap.id != before.uid) return;
    // Our own writes echo back before the server has them, and a cached
    // snapshot can be older than what the session last read from the server.
    // Neither one is news.
    if (snap.metadata.hasPendingWrites || snap.metadata.isFromCache) return;
    final data = snap.data();
    final after = data == null ? null : {...data, 'uid': snap.id};
    switch (MembershipAccess.classify(before, after)) {
      case AccessChange.none:
        return;
      case AccessChange.accountRemoved:
        unawaited(_endSessionAfterRemoval(before.companyName));
      case AccessChange.removedFromWorkspace:
        _adoptServerUser(after!);
        final notice = _lostAccessNotice(before.companyName);
        _raiseAccessNotice(notice);
        notifyListeners();
        unawaited(_explainLostAccess(before, notice));
      case AccessChange.updated:
        _adoptServerUser(after!);
        notifyListeners();
    }
  }

  /// Sharpens [notice] once it is known that an admin removed the account,
  /// rather than the workspace being purged or the user leaving it elsewhere.
  Future<void> _explainLostAccess(UserModel before, String notice) async {
    final removed = await _authService.wasRemovedFrom(
      companyId: before.companyId,
      uid: before.uid,
    );
    if (!removed || _accessNotice != notice) return;
    _accessNotice = _removedByAdminNotice(before.companyName);
    notifyListeners();
  }

  void _adoptServerUser(Map<String, dynamic> data) {
    _currentUser = UserModel.fromMap(data);
    _resolveUserPermissions();
  }

  /// Signs out an account whose user doc is gone. Without that doc every rule
  /// refuses it, so there is nothing left to keep the session open for.
  Future<void> _endSessionAfterRemoval(String companyName) async {
    _stopWatchingUserDoc();
    detachRoleProvider();
    _clearInspection();
    // Cleared before signing out so the auth listener does not also report an
    // expired session on top of the clearer notice below.
    _currentUser = null;
    _sessionExpired = false;
    _raiseAccessNotice(
      '${_lostAccessNotice(companyName)} Contact an admin if this is a '
      'mistake.',
    );
    notifyListeners();
    try {
      await _authService.logout();
    } catch (_) {}
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
      // Only overrides this workspace set; the rules ignore the rest.
      overrides: _currentUser!.overridesApply
          ? _currentUser!.permissions
          : null,
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
        if (_currentUser == null) {
          // Signed in to Firebase, but the account record is gone: an older
          // build's "remove user" deleted it. The shell signs out next, and
          // used to do so with no word of why.
          _raiseAccessNotice(_noAccountRecordNotice);
        }
      } catch (e) {
        _currentUser = null;
        _errorMessage = friendlyError(
          e,
          fallback: 'Could not load account data.',
        );
      }
      _watchUserDoc();
      notifyListeners();
    }
    _listenAuthState();
  }

  void _listenAuthState() {
    _authStateSub?.cancel();
    _authStateSub = _authService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null && _currentUser != null) {
        _sessionExpired = !_signingOut;
        _stopWatchingUserDoc();
        detachRoleProvider();
        _clearInspection();
        _currentUser = null;
        notifyListeners();
      } else if (firebaseUser != null && _currentUser == null && !_isLoading) {
        try {
          _currentUser = await _authService.getUserData(firebaseUser.uid);
          _resolveUserPermissions();
          _watchUserDoc();
          notifyListeners();
        } catch (_) {}
      } else if (firebaseUser != null &&
          firebaseUser.uid == _currentUser?.uid) {
        // Back on this account after the session briefly belonged to another
        // one, which closed the doc listener.
        _watchUserDoc();
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
        _watchUserDoc();
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
      _watchUserDoc();
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
        _errorMessage = _noAccountRecordNotice;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _resolveUserPermissions();
      _watchUserDoc();
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
    // Before signing out, so the listener does not report the sign-out itself
    // as a permission error.
    _stopWatchingUserDoc();
    _signingOut = true;
    try {
      await _authService.logout();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _signingOut = false;
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

  /// Everyone holding a member doc in the workspace on screen, including people
  /// currently active in another workspace, whom [getAllUsers] cannot see.
  Stream<List<WorkspaceMember>> getWorkspaceMembers() {
    return _authService.watchMembers(currentUser?.companyId ?? '');
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

  /// Gives [uid] the role [roleId] in the current workspace. Returns whether
  /// it was saved; [errorMessage] says why not. It returned nothing, so the
  /// screen announced success even when the write was refused.
  Future<bool> updateUserRoleId(String uid, String roleId) async {
    // The real account's workspace, not the one being inspected.
    if (_refuseWhileInspecting()) return false;
    final companyId = _currentUser?.companyId ?? '';
    if (companyId.isEmpty) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    var ok = false;
    try {
      await _authService.updateUserRoleAssignment(
        uid,
        roleId,
        companyId: companyId,
      );
      ok = true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not change the role.');
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  Future<bool> updateStaffPermissions(
    String uid,
    Map<String, bool> perms,
  ) async {
    if (_isLoading) return false;
    if (_refuseWhileInspecting()) return false;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.updateUserPermissions(
        uid,
        perms,
        companyId: _currentUser?.companyId ?? '',
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
    // The account deletes its own user doc on the way out. That is not a
    // removal to report, so stop listening first.
    _stopWatchingUserDoc();
    notifyListeners();

    _signingOut = true;
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
      _watchUserDoc();
      notifyListeners();
      return false;
    } finally {
      _signingOut = false;
    }
  }

  /// Removes [uid] from the workspace on screen, and only from it.
  Future<bool> removeMember({
    required String uid,
    String name = '',
    String email = '',
  }) async {
    if (_isLoading) return false;
    if (uid == _currentUser?.uid) {
      _errorMessage =
          'You cannot remove yourself. To leave this workspace, use the '
          'company screen.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.removeMember(
        // The workspace on screen, so removing someone while inspecting revokes
        // them from the tenant being looked at rather than the inspector's own.
        companyId: currentUser?.companyId ?? '',
        uid: uid,
        removedByUid: _currentUser?.uid ?? '',
        name: name,
        email: email,
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
    if (_refuseWhileInspecting()) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final membership = await _authService.createNewCompany(
        uid: _currentUser!.uid,
        companyName: companyName,
      );
      _accessNotice = null;
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

  /// Switching, creating, joining and leaving all act on the real account, so
  /// each is refused mid-inspection: from the inspected workspace's own
  /// switcher they quietly changed the inspector's workspaces instead.
  Future<bool> switchCompany(CompanyMembership membership) async {
    if (_currentUser == null) return false;
    if (_refuseWhileInspecting()) return false;
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
      _accessNotice = null;
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // AuthService explains a refused switch in its own words (removed from
      // the workspace, or no member record yet); friendlyError keeps those.
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
    if (_refuseWhileInspecting()) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.joinCompany(
        uid: _currentUser!.uid,
        inviteCode: inviteCode,
      );
      _accessNotice = null;
      await refreshCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Its own explanations as written; a Firestore or network failure as a
      // sentence instead of the raw "[cloud_firestore/...]" text.
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not join with that code. Check it and try again.',
      );
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> leaveCompany(CompanyMembership membership) async {
    if (_currentUser == null) return false;
    if (_refuseWhileInspecting()) return false;
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
      // The admin's own session is left alone (registerStaff creates the
      // account on an Auth instance of its own), so there is nothing to
      // restore afterwards, and a mistyped password ends nothing.
      final newUser = await _authService.registerStaff(
        name: name,
        email: email,
        password: password,
        companyId: _currentUser?.companyId ?? '',
        companyName: _currentUser?.companyName ?? '',
        adminPassword: adminPassword,
        roleId: roleId,
      );
      _isLoading = false;
      notifyListeners();
      return newUser != null;
    } catch (e) {
      _errorMessage = e is FirebaseAuthException
          ? AuthService.getErrorMessage(e)
          : friendlyError(e, fallback: 'Could not create the staff account.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
