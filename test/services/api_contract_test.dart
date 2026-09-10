import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/generated/inventory_api.g.dart';

/// Keeps the Flutter client and the Python API honest about each other.
///
/// `RagApiService` parses the assistant's responses by hand, pulling values out
/// of a decoded map with string literals. That is deliberate — it handles
/// things a generated client would not — but it means every field name exists
/// twice, in two languages, with nothing between them. Rename `answered_by` on
/// the server and this app keeps compiling, keeps running, and reads null
/// forever.
///
/// So the wire keys are asserted, not assumed. `inventory_api.g.dart` is
/// generated from `rag_backend/openapi.json`, which is generated from the
/// FastAPI app; if a field is renamed or added server-side, one of these fails
/// and someone has to decide what the client does about it.
void main() {
  final repoRoot = Directory.current.path;
  final schemaFile = File('$repoRoot/rag_backend/openapi.json');
  final serviceFile = File('$repoRoot/lib/services/rag_api_service.dart');

  group('API contract', () {
    test('the committed schema is present and parses', () {
      expect(
        schemaFile.existsSync(),
        isTrue,
        reason: 'rag_backend/openapi.json is the contract; regenerate it with '
            'tools/export_openapi.py',
      );
      final schema = jsonDecode(schemaFile.readAsStringSync()) as Map<String, dynamic>;
      expect(schema['paths'], isNotEmpty);
    });

    test('generated models match the committed schema', () {
      final schema = jsonDecode(schemaFile.readAsStringSync()) as Map<String, dynamic>;
      final components =
          (schema['components'] as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;
      final declared = ((components['QueryResponse']
              as Map<String, dynamic>)['properties'] as Map<String, dynamic>)
          .keys
          .toList()
        ..sort();

      final generated = [...QueryResponse.wireKeys]..sort();
      expect(
        generated,
        equals(declared),
        reason: 'inventory_api.g.dart is stale. Regenerate:\n'
            '  cd rag_backend && venv/bin/python tools/generate_dart_client.py',
      );
    });

    test('every field the server sends is either read or knowingly ignored', () {
      final source = serviceFile.readAsStringSync();

      // Fields the server sends that this client deliberately does not read.
      //
      // `updated_catalog` is the expensive one: producing it costs the backend
      // a forced full re-read of the catalog on every turn that writes, and
      // nothing in this app consumes it. It is listed rather than removed
      // because dropping a field is an API change, not a client cleanup.
      const knowinglyIgnored = <String>{
        'analytics_data',
        'retries',
        'updated_catalog',
      };

      final unread = <String>[];
      for (final key in QueryResponse.wireKeys) {
        if (knowinglyIgnored.contains(key)) continue;
        if (!source.contains("'$key'") && !source.contains('"$key"')) {
          unread.add(key);
        }
      }

      expect(
        unread,
        isEmpty,
        reason: 'rag_api_service.dart never reads: $unread.\n'
            'Either parse them, or add them to knowinglyIgnored with a reason.',
      );
    });

    test('a full response payload decodes into the generated model', () {
      final payload = <String, dynamic>{
        'answer': '**2 low**',
        'retries': 0,
        'intent': 'ANALYTICS',
        'executed_actions': <Map<String, dynamic>>[],
        'analytics_data': <String, dynamic>{'total': 4},
        'updated_catalog': null,
        'answered_by': 'deterministic',
        'clarification_options': null,
        'pending_action': null,
        'response_kind': 'report',
        'items': <Map<String, dynamic>>[
          {'id': 'p_apples', 'name': 'Fresh Apples (kg)', 'barcode': '89010001'},
        ],
      };

      final decoded = QueryResponse.fromJson(payload);
      expect(decoded.answer, '**2 low**');
      expect(decoded.intent, 'ANALYTICS');
      expect(decoded.answeredBy, 'deterministic');
      expect(decoded.responseKind, 'report');
      expect(decoded.items, hasLength(1));
      expect(decoded.items!.first['barcode'], '89010001');
      expect(decoded.executedActions, isEmpty);
    });

    test('a minimal payload falls back to the schema defaults', () {
      // Only `answer` is required. Everything else has to survive being absent,
      // because an older backend genuinely will omit it.
      final decoded = QueryResponse.fromJson(<String, dynamic>{'answer': 'hi'});
      expect(decoded.answer, 'hi');
      expect(decoded.intent, 'KNOWLEDGE');
      expect(decoded.responseKind, 'prose');
      expect(decoded.retries, 0);
      expect(decoded.executedActions, isEmpty);
      expect(decoded.items, isNull);
    });

    test('round-tripping preserves every wire key', () {
      final decoded = QueryResponse.fromJson(<String, dynamic>{'answer': 'hi'});
      final encoded = decoded.toJson();
      for (final key in QueryResponse.wireKeys) {
        expect(
          encoded.containsKey(key),
          isTrue,
          reason: 'toJson drops $key, so a round-trip is lossy',
        );
      }
    });
  });
}
