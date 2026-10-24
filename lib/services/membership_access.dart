import 'dart:convert';

import '../models/user_model.dart';

/// What a server-confirmed change to the signed-in user's own doc means for
/// the session.
enum AccessChange {
  /// Nothing the session depends on changed.
  none,

  /// Something changed (a role, a permission, the active workspace), but the
  /// account still has the workspace it was using.
  updated,

  /// The account lost the workspace it was using: an admin removed it.
  removedFromWorkspace,

  /// The user doc is gone. The account can no longer do anything, because the
  /// security rules read that doc for every request.
  accountRemoved,
}

/// Decisions about workspace membership, kept free of Firebase so they can be
/// unit tested.
class MembershipAccess {
  MembershipAccess._();

  /// [data]'s `companyMemberships` with every entry for [companyId] removed.
  static List<Map<String, dynamic>> membershipsWithout(
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

  /// The update that detaches an account from [companyId] when an admin
  /// removes it from that workspace.
  ///
  /// The account is left in the workspace-less state rather than deleted.
  /// Deleting the doc used to take every other workspace the person belonged
  /// to with it, including one they owned, and left a login that could no
  /// longer be used or re-registered. Their other memberships survive here,
  /// and the app lets them pick one, join another, or create their own.
  ///
  /// `roleId` is '' rather than 'staff' on purpose. The assistant backend
  /// resolves a caller's permissions from this doc's roleId against whichever
  /// workspace the request names. It caches membership for a few minutes, so
  /// for that window 'staff' would still resolve to this workspace's staff
  /// grants. '' resolves to nothing. Per-user permission overrides are cleared
  /// for the same reason: this workspace granted them.
  static Map<String, dynamic> detachFields(
    Map<String, dynamic> data,
    String companyId,
  ) {
    return {
      'companyId': '',
      'companyName': '',
      'role': 'staff',
      'roleId': '',
      'permissions': <String, bool>{},
      'companyMemberships': membershipsWithout(data, companyId),
    };
  }

  /// Classifies the change from [before], the session's copy of the user, to
  /// [after], the user doc as the server now has it (null when it is gone).
  static AccessChange classify(UserModel before, Map<String, dynamic>? after) {
    if (after == null) return AccessChange.accountRemoved;
    final fresh = UserModel.fromMap(after);
    final active = before.companyId;
    if (active.isNotEmpty &&
        fresh.companyId != active &&
        !fresh.companyMemberships.any((m) => m.companyId == active)) {
      return AccessChange.removedFromWorkspace;
    }
    return fingerprint(fresh) == fingerprint(before)
        ? AccessChange.none
        : AccessChange.updated;
  }

  /// Everything about [user] that the session acts on, as one comparable
  /// string. Permission keys are sorted so map order cannot register as a
  /// change.
  static String fingerprint(UserModel user) {
    final perms = user.permissions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return jsonEncode([
      user.uid,
      user.name,
      user.email,
      user.phone,
      user.role,
      user.roleId,
      user.companyId,
      user.companyName,
      [
        for (final e in perms) [e.key, e.value],
      ],
      [
        for (final m in user.companyMemberships)
          [m.companyId, m.companyName, m.role, m.roleId],
      ],
    ]);
  }
}
