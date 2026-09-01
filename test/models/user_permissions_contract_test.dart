import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/user_model.dart';

void main() {
  /// The user doc AuthService.register writes for a new workspace owner.
  UserModel ownerDoc({Map<String, bool>? permissions}) => UserModel(
    uid: 'u1',
    name: 'Owner',
    email: 'o@acme.com',
    role: 'admin',
    roleId: 'owner',
    companyId: 'c1',
    companyName: 'Acme',
    phone: '9999999999',
    createdAt: DateTime(2026, 1, 1),
    permissions: permissions,
  );

  group('self-created user doc', () {
    test('carries no permission grants', () {
      // firestore.rules refuses a self-created user doc that carries permission
      // overrides, because that map is a privilege grant. Omitting the argument
      // makes UserModel fall back to defaultPermissions, which is NOT empty —
      // that is what silently broke signup: the company was created, then the
      // user doc was denied, leaving an account that could neither be used nor
      // re-registered.
      final map = ownerDoc(permissions: const {}).toMap();
      expect(map['permissions'], isEmpty);
    });

    test('defaultPermissions is non-empty, so it must never be the fallback '
        'for a self-created doc', () {
      expect(UserModel.defaultPermissions, isNotEmpty);
      expect(ownerDoc().toMap()['permissions'], isNotEmpty);
    });

    test('an owner still has every permission despite an empty stored map', () {
      // effectivePermissions short-circuits on isAdmin, so dropping the stored
      // map costs the owner nothing in the UI.
      final owner = ownerDoc(permissions: const {});
      expect(owner.isAdmin, isTrue);
      expect(owner.hasPermission('canManageUsers'), isTrue);
      expect(owner.hasPermission('canDeleteProducts'), isTrue);
    });

    test('a staff user with an empty stored map still gets the defaults', () {
      final staff = UserModel(
        uid: 'u2',
        name: 'Staff',
        email: 's@acme.com',
        role: 'staff',
        roleId: 'staff',
        companyId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        permissions: const {},
      );
      expect(staff.isAdmin, isFalse);
      expect(staff.effectivePermissions, isNotEmpty);
    });
  });
}
