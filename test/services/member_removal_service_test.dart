import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/member_removal_service.dart';

/// The shape of the writes a removal makes. Whether the security rules accept
/// them is pinned against the real engine in test/rules/firestore_rules_test.mjs
/// (the MEMBER REMOVAL section). `fake_cloud_firestore` has no rules.
void main() {
  late FakeFirebaseFirestore db;
  late MemberRemovalService service;

  DocumentReference<Map<String, dynamic>> user(String uid) =>
      db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> member(String cid, String uid) =>
      db.collection('companies').doc(cid).collection('members').doc(uid);
  DocumentReference<Map<String, dynamic>> removal(String cid, String uid) =>
      db.collection('companies').doc(cid).collection('removedMembers').doc(uid);

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = MemberRemovalService(firestore: db);
    // Bob works in A, and also belongs to B.
    await user('bob').set({
      'uid': 'bob',
      'name': 'Bob',
      'email': 'bob@a.test',
      'role': 'staff',
      'roleId': 'staff',
      'companyId': 'A',
      'companyName': 'Acme',
      'permissions': {'canStockIn': true},
      'companyMemberships': [
        {'companyId': 'A', 'companyName': 'Acme', 'role': 'staff'},
        {'companyId': 'B', 'companyName': 'Beta', 'role': 'staff'},
      ],
    });
    await member('A', 'bob').set({'uid': 'bob', 'role': 'staff'});
    await member('B', 'bob').set({'uid': 'bob', 'role': 'staff'});
  });

  group('removeMember', () {
    test('deletes the member doc and records the removal', () async {
      await service.removeMember(
        companyId: 'A',
        uid: 'bob',
        removedByUid: 'owner',
        name: 'Bob',
        email: 'bob@a.test',
      );

      expect((await member('A', 'bob').get()).exists, isFalse);
      final record = (await removal('A', 'bob').get()).data()!;
      expect(record['uid'], 'bob');
      expect(record['name'], 'Bob');
      expect(record['email'], 'bob@a.test');
      expect(record['removedBy'], 'owner');
      expect(record['removedAt'], isA<Timestamp>());
    });

    test('detaches the account instead of deleting it', () async {
      await service.removeMember(companyId: 'A', uid: 'bob');

      final doc = await user('bob').get();
      expect(doc.exists, isTrue, reason: 'the account must survive');
      final data = doc.data()!;
      expect(data['companyId'], '');
      expect(data['companyName'], '');
      expect(data['role'], 'staff');
      expect(data['roleId'], '');
      expect(data['name'], 'Bob');
      // Not asserted here: the permission overrides being cleared. The fake
      // merges a map passed to update() into the old one, where Firestore
      // replaces it, so it would report the old overrides. detachFields is
      // tested for the empty map in membership_access_test.dart, and the real
      // engine's result in test/rules/firestore_rules_test.mjs.
    });

    test('leaves every other workspace intact', () async {
      await service.removeMember(companyId: 'A', uid: 'bob');

      final memberships =
          ((await user('bob').get()).data()!['companyMemberships'] as List)
              .map((m) => (m as Map)['companyId'])
              .toList();
      expect(memberships, ['B']);
      expect((await member('B', 'bob').get()).exists, isTrue);
    });

    test(
      'does not touch a user doc that points at another workspace',
      () async {
        await user('bob').update({'companyId': 'B', 'companyName': 'Beta'});
        final before = (await user('bob').get()).data();

        await service.removeMember(companyId: 'A', uid: 'bob');

        expect((await user('bob').get()).data(), before);
        expect((await member('A', 'bob').get()).exists, isFalse);
        expect((await removal('A', 'bob').get()).exists, isTrue);
      },
    );

    test(
      'still revokes membership when the user doc is already gone',
      () async {
        // Accounts removed by older builds had their user doc deleted.
        await user('bob').delete();

        await service.removeMember(companyId: 'A', uid: 'bob');

        expect((await member('A', 'bob').get()).exists, isFalse);
        expect((await removal('A', 'bob').get()).exists, isTrue);
        expect((await user('bob').get()).exists, isFalse);
      },
    );

    test('refuses to run without a workspace, and writes nothing', () async {
      await expectLater(
        service.removeMember(companyId: ' ', uid: 'bob'),
        throwsStateError,
      );
      expect((await member('A', 'bob').get()).exists, isTrue);
      expect((await user('bob').get()).data()!['companyId'], 'A');
    });
  });

  group('wasRemovedFrom', () {
    test('is true only after a removal', () async {
      expect(await service.wasRemovedFrom(companyId: 'A', uid: 'bob'), isFalse);
      await service.removeMember(companyId: 'A', uid: 'bob');
      expect(await service.wasRemovedFrom(companyId: 'A', uid: 'bob'), isTrue);
      expect(await service.wasRemovedFrom(companyId: 'B', uid: 'bob'), isFalse);
    });

    test('is false for empty ids', () async {
      expect(await service.wasRemovedFrom(companyId: '', uid: 'bob'), isFalse);
      expect(await service.wasRemovedFrom(companyId: 'A', uid: ''), isFalse);
    });
  });

  group('watchMembers', () {
    test('lists member docs, falling back to the doc id for the uid', () async {
      await member('A', 'legacy').set({'role': 'staff'});

      final members = await service.watchMembers('A').first;
      final byUid = {for (final m in members) m.uid: m};
      expect(byUid.keys, containsAll(['bob', 'legacy']));
      expect(byUid['legacy']!.displayName, 'Member');
    });

    test('emits nothing to list for an empty workspace id', () async {
      expect(await service.watchMembers('').first, isEmpty);
    });
  });
}
