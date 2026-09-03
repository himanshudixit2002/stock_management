import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/company_settings_writer.dart';

/// These tests exist because of a bug that produced no error anywhere.
///
/// Every settings write in the app was
/// `set({'settings.locations': ...}, SetOptions(merge: true))`. Firestore reads
/// a dotted string key as a field *path* in `update()` but as a *literal field
/// name* in `set()`, so those writes created a top-level field genuinely named
/// `"settings.locations"` and never touched the nested map the providers read
/// back. The providers update their own state optimistically, so every change
/// appeared to work and was gone on the next cold start.
///
/// **Scope note.** `fake_cloud_firestore` does not reproduce that distinction —
/// it nests a dotted key in `set()` as well as `update()` — so the defect
/// itself, and the migration that repairs data left behind by it, cannot be
/// demonstrated here. Those are pinned against the real engine in
/// `test/rules/settings_write_semantics.mjs`, which runs on the Firestore
/// emulator. What the fake models faithfully, and what this file covers, is the
/// shape of the writes this class performs.
void main() {
  late FakeFirebaseFirestore firestore;
  late DocumentReference<Map<String, dynamic>> doc;
  late CompanySettingsWriter writer;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    doc = firestore.collection('companies').doc('c1');
    writer = CompanySettingsWriter(doc);
  });

  Future<Map<String, dynamic>> read() async => (await doc.get()).data() ?? {};

  group('write', () {
    test('lands in the nested settings map', () async {
      await doc.set({'settings': <String, dynamic>{}});
      await writer.write('pricingEnabled', false);

      final data = await read();
      expect((data['settings'] as Map)['pricingEnabled'], isFalse);
      expect(data.containsKey('settings.pricingEnabled'), isFalse);
    });

    test('survives a re-read, which is what the bug broke', () async {
      await doc.set({'settings': <String, dynamic>{}});
      await writer.write('locations', ['Bay 3']);
      await writer.write('sizes', ['L']);

      final settings = (await read())['settings'] as Map;
      expect(settings['locations'], ['Bay 3']);
      expect(settings['sizes'], ['L']);
    });

    test('is field-scoped, so two writes do not clobber each other', () async {
      await doc.set({
        'settings': {'pricingEnabled': true, 'vendorsEnabled': true},
      });
      await writer.write('pricingEnabled', false);

      final settings = (await read())['settings'] as Map;
      expect(settings['pricingEnabled'], isFalse);
      expect(settings['vendorsEnabled'], isTrue, reason: 'untouched key kept');
    });

    test('arrayUnion works nested', () async {
      await doc.set({
        'settings': {
          'locations': ['A'],
        },
      });
      await writer.write('locations', FieldValue.arrayUnion(['B']));

      expect(((await read())['settings'] as Map)['locations'], ['A', 'B']);
    });

    test('a prefix writes one level deeper', () async {
      await doc.set({'settings': <String, dynamic>{}});
      await writer.writeAll({
        'currencySymbol': r'$',
        'invoicePrefix': 'INV',
      }, prefix: 'billing');

      final billing =
          ((await read())['settings'] as Map)['billing'] as Map;
      expect(billing['currencySymbol'], r'$');
      expect(billing['invoicePrefix'], 'INV');
    });

    test('falls back to a nested set when the document does not exist',
        () async {
      // No doc.set() first — update() would throw not-found.
      await writer.write('locations', ['Bay 3']);

      expect(((await read())['settings'] as Map)['locations'], ['Bay 3']);
    });

    test('an empty field map is a no-op', () async {
      await doc.set({'settings': <String, dynamic>{}});
      await writer.writeAll({});
      expect((await read())['settings'], isEmpty);
    });
  });

  group('healFlatKeys', () {
    // Only the no-op path is testable here: the fake cannot produce a document
    // carrying a flat `settings.x` field, because its set() nests the key the
    // same way update() does. The folding, the deletion, and "a nested value
    // wins over a stranded one" are covered against the real engine in
    // test/rules/settings_write_semantics.mjs.
    test('returns null when there is nothing to heal', () async {
      await doc.set({
        'settings': {'sizes': <String>[]},
      });
      expect(await writer.healFlatKeys(await read()), isNull);
    });

    test('returns null for a document with no settings at all', () async {
      await doc.set({'companyName': 'Acme'});
      expect(await writer.healFlatKeys(await read()), isNull);
    });
  });
}
