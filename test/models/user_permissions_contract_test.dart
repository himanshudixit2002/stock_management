import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/permissions.dart';
import 'package:stock_management/models/role_model.dart';
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

  group('permissions added after the granular split', () {
    UserModel legacyStaff() => UserModel(
      uid: 'u3',
      name: 'Legacy',
      email: 'l@acme.com',
      role: 'staff',
      // No roleId: this user predates RBAC, so effectivePermissions falls back
      // to defaultPermissions instead of resolving through a role document.
      companyId: 'c1',
      createdAt: DateTime(2026, 1, 1),
      permissions: const {},
    );

    test('allPermissionKeys is the pre-split legacy set, not the live one', () {
      // This is the load-bearing fact behind the test below, and it is not
      // obvious: the list still names coarse keys like canManageProducts that
      // AppPermissions replaced with granular ones. Anything added since is
      // absent from it by construction.
      expect(UserModel.allPermissionKeys, contains('canManageProducts'));
      expect(
        UserModel.allPermissionKeys.length,
        lessThan(AppPermissions.allKeys.length),
      );
    });

    test('a legacy user is denied every permission added since the split', () {
      // This is what makes shipping a new module safe: nobody silently gains
      // its controls on the day they update. An admin grants them through a
      // role, deliberately.
      final staff = legacyStaff();
      for (final key in [
        'canApproveRequisitions',
        'canManageLandedCosts',
        'canManagePriceLists',
        'canManageRecurringInvoices',
        'canBuildAssemblies',
        'canManageSerials',
        'canCreateTransferOrders',
        'canPrintLabels',
        'canViewTaxReports',
        // The second wave of modules, held to the same rule.
        'canManageQuotations',
        'canConvertQuotations',
        'canDispatchShipments',
        'canManageExpenses',
        'canManageRegisterSessions',
        'canManageCreditLimits',
        'canViewVendorScorecard',
        'canManageCommissions',
        'canManageBudgets',
        'canManageServiceJobs',
        'canIssueJobWork',
        'canReceiveJobWork',
      ]) {
        expect(staff.hasPermission(key), isFalse, reason: key);
      }
    });

    test('a role user is denied a key its role document does not carry', () {
      // The other half of the same guarantee, for the RBAC population.
      final role = RoleModel(
        id: 'viewer',
        name: 'Viewer',
        permissions: const {'canViewProducts': true},
        companyId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(role.hasPermission('canViewProducts'), isTrue);
      expect(role.hasPermission('canApproveRequisitions'), isFalse);
    });

    test('an admin still holds every permission, new ones included', () {
      final owner = ownerDoc(permissions: const {});
      for (final key in AppPermissions.allKeys) {
        expect(owner.hasPermission(key), isTrue, reason: key);
      }
    });
  });
}
