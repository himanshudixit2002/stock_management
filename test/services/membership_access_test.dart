import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/user_model.dart';
import 'package:stock_management/services/membership_access.dart';

void main() {
  /// A staff member of workspace A who also belongs to workspace B, as the
  /// session holds them.
  UserModel member({
    String companyId = 'A',
    String role = 'staff',
    String roleId = 'staff',
    Map<String, bool> permissions = const {'canStockIn': true},
  }) => UserModel(
    uid: 'bob',
    name: 'Bob',
    email: 'bob@a.test',
    role: role,
    roleId: roleId,
    companyId: companyId,
    companyName: companyId == 'A' ? 'Acme' : '',
    createdAt: DateTime(2026, 1, 1),
    permissions: permissions,
    companyMemberships: const [
      CompanyMembership(companyId: 'A', companyName: 'Acme', role: 'staff'),
      CompanyMembership(companyId: 'B', companyName: 'Beta', role: 'staff'),
    ],
  );

  /// The same account as its user doc reads on the server.
  Map<String, dynamic> docOf(UserModel user) => user.toMap();

  group('membershipsWithout', () {
    test('drops every entry for the workspace and keeps the rest', () {
      final data = {
        'companyMemberships': [
          {'companyId': 'A', 'role': 'staff'},
          {'companyId': 'B', 'role': 'staff'},
          {'companyId': 'A', 'role': 'admin'},
        ],
      };
      expect(MembershipAccess.membershipsWithout(data, 'A'), [
        {'companyId': 'B', 'role': 'staff'},
      ]);
    });

    test('copes with a doc that has no membership list', () {
      expect(MembershipAccess.membershipsWithout({}, 'A'), isEmpty);
      expect(
        MembershipAccess.membershipsWithout({'companyMemberships': 'x'}, 'A'),
        isEmpty,
      );
    });
  });

  group('detachFields', () {
    test('leaves the account in no workspace with nothing granted', () {
      final fields = MembershipAccess.detachFields(docOf(member()), 'A');
      expect(fields['companyId'], '');
      expect(fields['companyName'], '');
      expect(fields['role'], 'staff');
      // Not 'staff': the assistant backend would resolve that against the
      // workspace's staff role while its membership cache is still warm.
      expect(fields['roleId'], '');
      expect(fields['permissions'], isEmpty);
    });

    test('keeps the other workspaces the person belongs to', () {
      final fields = MembershipAccess.detachFields(docOf(member()), 'A');
      final kept = (fields['companyMemberships'] as List)
          .map((m) => (m as Map)['companyId'])
          .toList();
      expect(kept, ['B']);
    });
  });

  group('classify', () {
    test('a deleted user doc means the account was removed', () {
      expect(
        MembershipAccess.classify(member(), null),
        AccessChange.accountRemoved,
      );
    });

    test('being detached from the active workspace is a removal', () {
      final after = {
        ...docOf(member()),
        ...MembershipAccess.detachFields(docOf(member()), 'A'),
      };
      expect(
        MembershipAccess.classify(member(), after),
        AccessChange.removedFromWorkspace,
      );
    });

    test(
      'losing the active workspace while landing in another is a removal',
      () {
        final after = {
          ...docOf(member()),
          'companyId': 'B',
          'companyName': 'Beta',
          'companyMemberships': [
            {'companyId': 'B', 'companyName': 'Beta', 'role': 'staff'},
          ],
        };
        expect(
          MembershipAccess.classify(member(), after),
          AccessChange.removedFromWorkspace,
        );
      },
    );

    test('switching elsewhere while still a member is not a removal', () {
      // A switch made on another device: A is still on the list.
      final after = {...docOf(member()), 'companyId': 'B'};
      expect(MembershipAccess.classify(member(), after), AccessChange.updated);
    });

    test('a role an admin changed is picked up', () {
      final after = docOf(member(role: 'manager', roleId: 'manager'));
      expect(MembershipAccess.classify(member(), after), AccessChange.updated);
    });

    test('a revoked permission is picked up', () {
      final after = docOf(member(permissions: const {'canStockIn': false}));
      expect(MembershipAccess.classify(member(), after), AccessChange.updated);
    });

    test('an unchanged doc is not news', () {
      expect(
        MembershipAccess.classify(member(), docOf(member())),
        AccessChange.none,
      );
    });

    test('permission map order does not count as a change', () {
      final before = member(
        permissions: const {'canStockIn': true, 'canStockOut': false},
      );
      final after = {
        ...docOf(before),
        'permissions': {'canStockOut': false, 'canStockIn': true},
      };
      expect(MembershipAccess.classify(before, after), AccessChange.none);
    });

    test(
      'joining a workspace from the workspace-less state is not a removal',
      () {
        final before = member(companyId: '');
        final after = docOf(member());
        expect(MembershipAccess.classify(before, after), AccessChange.updated);
      },
    );
  });
}
