import '../utils/parse_helpers.dart';

/// A `companies/{companyId}/members/{uid}` doc: the server-verified record that
/// an account belongs to a workspace.
///
/// User Management reads these as well as user docs because a user doc is only
/// readable to an admin while its active workspace is the admin's. A member who
/// has switched to another workspace is invisible in the user list, yet still
/// holds access here and can switch back at any time. Listing member docs is the
/// only way the admin can see, and remove, them.
class WorkspaceMember {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String roleId;

  const WorkspaceMember({
    required this.uid,
    this.name = '',
    this.email = '',
    this.role = 'staff',
    this.roleId = '',
  });

  factory WorkspaceMember.fromMap(String id, Map<String, dynamic> map) {
    final uid = safeString(map['uid']);
    return WorkspaceMember(
      uid: uid.isNotEmpty ? uid : id,
      name: safeString(map['name']).trim(),
      email: safeString(map['email']).trim(),
      role: safeString(map['role'], 'staff'),
      roleId: safeString(map['roleId']),
    );
  }

  /// Member docs written by older builds can lack a name or an email.
  String get displayName {
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Member';
  }
}
