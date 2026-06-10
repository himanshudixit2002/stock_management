import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../config/permissions.dart';
import '../models/role_model.dart';

class RoleProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<RoleModel> _roles = [];
  bool _isLoading = false;
  bool _isBackfilling = false;
  String? _errorMessage;
  String _companyId = '';
  StreamSubscription? _subscription;

  List<RoleModel> get roles => _roles;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  RoleModel? getRoleById(String roleId) {
    final idx = _roles.indexWhere((r) => r.id == roleId);
    return idx == -1 ? null : _roles[idx];
  }

  CollectionReference get _rolesRef =>
      _firestore.collection('companies').doc(_companyId).collection('roles');

  void initialize({required String companyId}) {
    if (_companyId == companyId && _subscription != null) return;
    _subscription?.cancel();
    _subscription = null;
    if (_companyId != companyId) {
      _roles = [];
    }
    _companyId = companyId;
    _backfillSystemRolePermissions();
    _subscription = _rolesRef
        .orderBy('createdAt')
        .snapshots()
        .listen(
          (snapshot) {
            _roles = snapshot.docs
                .map(
                  (doc) => RoleModel.fromMap(
                    doc.data() as Map<String, dynamic>,
                    id: doc.id,
                  ),
                )
                .toList();
            notifyListeners();
          },
          onError: (e) {
            _errorMessage = e.toString();
            notifyListeners();
          },
        );
  }

  Future<void> _backfillSystemRolePermissions() async {
    if (_companyId.isEmpty || _isBackfilling) return;
    _isBackfilling = true;
    try {
      final defaults = {
        for (final role in RoleModel.defaultRoles(_companyId)) role.id: role,
      };
      final roleIds = [
        RoleModel.ownerRoleId,
        RoleModel.adminRoleId,
        RoleModel.managerRoleId,
        RoleModel.staffRoleId,
        RoleModel.viewerRoleId,
      ];
      for (final roleId in roleIds) {
        final roleDoc = await _rolesRef.doc(roleId).get();
        if (!roleDoc.exists) continue;
        final data = roleDoc.data() as Map<String, dynamic>? ?? {};
        final rawPerms = data['permissions'];
        if (rawPerms is! Map) continue;
        final currentPerms = rawPerms.map(
          (k, v) => MapEntry(k.toString(), v == true),
        );
        final defaultPerms = defaults[roleId]?.permissions ?? const {};
        var changed = false;
        final merged = Map<String, bool>.from(currentPerms);
        for (final key in AppPermissions.allKeys) {
          if (!merged.containsKey(key)) {
            merged[key] = defaultPerms[key] ?? false;
            changed = true;
          }
        }
        if (changed) {
          await _rolesRef.doc(roleId).update({
            'permissions': merged,
            'updatedAt': Timestamp.now(),
          });
        }
      }
    } catch (_) {
      // Best-effort backfill only; stream initialization should continue.
    } finally {
      _isBackfilling = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _roles = [];
    _companyId = '';
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Seed default system roles if the collection is empty.
  Future<void> seedDefaultRoles(String companyId) async {
    final snapshot = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('roles')
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) return;

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

  Future<void> addRole(RoleModel role) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _rolesRef.add(role.toMap());
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateRole(RoleModel role) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _rolesRef.doc(role.id).update({
        'name': role.name,
        'description': role.description,
        'permissions': role.permissions,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> deleteRole(String roleId) async {
    final role = getRoleById(roleId);
    if (role == null) return false;
    if (role.isSystem && role.id == RoleModel.ownerRoleId) return false;

    _isLoading = true;
    notifyListeners();
    try {
      await _rolesRef.doc(roleId).delete();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<RoleModel?> duplicateRole(RoleModel source, String newName) async {
    final now = DateTime.now();
    final dup = RoleModel(
      id: '',
      name: newName,
      description: 'Copy of ${source.name}',
      permissions: Map<String, bool>.from(source.permissions),
      isSystem: false,
      companyId: _companyId,
      createdAt: now,
      updatedAt: now,
    );
    _isLoading = true;
    notifyListeners();
    try {
      final docRef = await _rolesRef.add(dup.toMap());
      _isLoading = false;
      notifyListeners();
      return dup.copyWith(id: docRef.id);
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Returns permissions for a role, with all keys present.
  Map<String, bool> resolvePermissions({
    required String roleId,
    Map<String, bool>? overrides,
  }) {
    final role = getRoleById(roleId);
    final base = role?.permissions ?? AppPermissions.allFalse();
    if (overrides == null || overrides.isEmpty) return base;
    final allowed = AppPermissions.allKeys.toSet();
    final filtered = <String, bool>{
      for (final e in overrides.entries)
        if (allowed.contains(e.key)) e.key: e.value,
    };
    if (filtered.isEmpty) return base;
    return {...base, ...filtered};
  }
}
