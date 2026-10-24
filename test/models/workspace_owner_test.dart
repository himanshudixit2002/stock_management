import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/role_model.dart';
import 'package:stock_management/models/user_model.dart';
import 'package:stock_management/models/workspace_member_model.dart';

void main() {
  UserModel user({required String role, required String roleId}) => UserModel(
    uid: 'u1',
    name: 'Someone',
    email: 's@acme.test',
    role: role,
    roleId: roleId,
    companyId: 'c1',
    createdAt: DateTime(2026, 1, 1),
    permissions: const {},
  );

  group('UserModel.isOwner', () {
    test('recognises the founder as AuthService.register writes them', () {
      // role 'admin' with roleId 'owner'. The old check read role alone, never
      // matched, and so never kept "Remove User" off the owner.
      expect(
        user(role: 'admin', roleId: RoleModel.ownerRoleId).isOwner,
        isTrue,
      );
    });

    test('still recognises a legacy owner role field', () {
      expect(user(role: 'owner', roleId: '').isOwner, isTrue);
    });

    test('an ordinary admin is not the owner', () {
      expect(
        user(role: 'admin', roleId: RoleModel.adminRoleId).isOwner,
        isFalse,
      );
    });

    test('a staff member is not the owner', () {
      expect(
        user(role: 'staff', roleId: RoleModel.staffRoleId).isOwner,
        isFalse,
      );
    });
  });

  group('WorkspaceMember', () {
    test('prefers the uid field, and falls back to the doc id', () {
      expect(WorkspaceMember.fromMap('doc1', {'uid': 'u9'}).uid, 'u9');
      expect(WorkspaceMember.fromMap('doc1', const {}).uid, 'doc1');
    });

    test('names itself by name, then email, then a placeholder', () {
      expect(
        WorkspaceMember.fromMap('d', {
          'name': ' Asha ',
          'email': 'a@x',
        }).displayName,
        'Asha',
      );
      expect(WorkspaceMember.fromMap('d', {'email': 'a@x'}).displayName, 'a@x');
      expect(WorkspaceMember.fromMap('d', const {}).displayName, 'Member');
    });
  });
}
