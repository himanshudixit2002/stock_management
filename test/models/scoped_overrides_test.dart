import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/return_model.dart';
import 'package:stock_management/models/user_model.dart';

UserModel _user({
  String companyId = 'A',
  String scope = '',
  List<String> memberships = const ['A'],
}) => UserModel(
  uid: 'u',
  name: 'U',
  email: 'u@x.com',
  role: 'staff',
  companyId: companyId,
  createdAt: DateTime(2024),
  permissions: const {'canExport': true},
  permissionsCompanyId: scope,
  companyMemberships: [
    for (final id in memberships)
      CompanyMembership(companyId: id, companyName: id, role: 'staff'),
  ],
);

void main() {
  group('per-user overrides apply only where they were set', () {
    test('in the workspace that scoped them', () {
      expect(_user(scope: 'A').overridesApply, isTrue);
    });

    test('not in another workspace', () {
      expect(
        _user(companyId: 'B', scope: 'A', memberships: ['A', 'B']).overridesApply,
        isFalse,
      );
    });

    test('unscoped ones only for an account in one workspace', () {
      expect(_user().overridesApply, isTrue);
      expect(
        _user(companyId: 'B', memberships: ['A', 'B']).overridesApply,
        isFalse,
      );
    });

    test('the scope survives a round trip', () {
      final map = _user(scope: 'A').toMap();
      expect(map['permissionsCompanyId'], 'A');
      expect(UserModel.fromMap(map).permissionsCompanyId, 'A');
    });
  });

  test('a return remembers which lines already moved stock', () {
    final r = ReturnModel(
      id: 'r1',
      type: ReturnType.customerReturn,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      stockAppliedLines: const [0, 2],
    );
    final map = r.toMap();
    expect(map['stockAppliedLines'], [0, 2]);
    expect(ReturnModel.fromMap(map, 'r1').stockAppliedLines, [0, 2]);
    // A return that has moved nothing writes nothing extra.
    expect(
      ReturnModel(
        id: 'r2',
        type: ReturnType.vendorReturn,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ).toMap().containsKey('stockAppliedLines'),
      isFalse,
    );
  });
}
