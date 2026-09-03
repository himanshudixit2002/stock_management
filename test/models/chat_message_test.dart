import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/chat_message.dart';

void main() {
  group('ChatMessage persistence', () {
    test('round-trips every field, including the ones that used to be dropped',
        () {
      // The old encoder wrote seven fields and silently omitted pendingAction
      // and responseKind, so a confirm card vanished whenever history reloaded.
      final original = ChatMessage(
        text: 'Reorder 20 units?',
        role: ChatRole.assistant,
        actionPayload: const {'type': 'stock_in', 'qty': 20},
        statsPayload: const {'total_products': 240},
        itemsPayload: const [
          {'name': 'Cannula', 'stock': 4},
        ],
        clarificationOptions: const [
          {'barcode': 'BC1', 'name': 'Cannula 18G'},
        ],
        pendingAction: const {'id': 'pa_1', 'kind': 'stock_in'},
        responseKind: 'preview',
        answeredBy: 'deterministic',
        isActionExecuted: true,
      );

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.text, original.text);
      expect(restored.role, ChatRole.assistant);
      expect(restored.createdAt, original.createdAt);
      expect(restored.actionPayload, original.actionPayload);
      expect(restored.statsPayload, original.statsPayload);
      expect(restored.itemsPayload, original.itemsPayload);
      expect(restored.clarificationOptions, original.clarificationOptions);
      expect(restored.pendingAction, original.pendingAction);
      expect(restored.responseKind, 'preview');
      expect(restored.answeredBy, 'deterministic');
      expect(restored.isActionExecuted, isTrue);
    });

    test('a half-streamed message comes back as complete, not streaming', () {
      // There is no stream to resume after a reload; restoring it as streaming
      // would leave a cursor blinking forever.
      final streaming = ChatMessage(
        text: 'Partial ans',
        role: ChatRole.assistant,
        status: ChatStatus.streaming,
      );
      expect(ChatMessage.fromJson(streaming.toJson()).status,
          ChatStatus.complete);
    });

    test('a failed message stays failed, so Retry survives a reload', () {
      final failed = ChatMessage(
        text: '',
        role: ChatRole.assistant,
        status: ChatStatus.failed,
      );
      expect(ChatMessage.fromJson(failed.toJson()).status, ChatStatus.failed);
    });

    test('reads the old isUser records that are already on disk', () {
      // Existing users have history written by the previous encoder.
      final legacy = ChatMessage.fromJson({
        'text': 'how much stock do I have?',
        'isUser': true,
        'isActionExecuted': false,
      });
      expect(legacy.role, ChatRole.user);
      expect(legacy.text, 'how much stock do I have?');
      // Missing id and timestamp are synthesised rather than throwing.
      expect(legacy.id, isNotEmpty);
      expect(legacy.createdAt, isNotNull);
      expect(legacy.status, ChatStatus.complete);
    });

    test('survives a record with nothing in it', () {
      final empty = ChatMessage.fromJson(const {});
      expect(empty.text, '');
      expect(empty.role, ChatRole.assistant);
      expect(empty.isUser, isFalse);
    });

    test('ignores payloads stored with the wrong shape', () {
      // These maps come off disk; one bad record must not take the history out.
      final odd = ChatMessage.fromJson(const {
        'text': 'x',
        'role': 'assistant',
        'statsPayload': 'not a map',
        'clarificationOptions': 'not a list',
        'itemsPayload': [1, 2, 'three'],
      });
      expect(odd.statsPayload, isNull);
      expect(odd.clarificationOptions, isNull);
      expect(odd.itemsPayload, isEmpty);
    });

    test('reads item rows stored under the old key', () {
      // Transcripts written before the field carried reorder plans and bulk
      // targets used `lowStockItemsPayload`; they must still open.
      final legacy = ChatMessage.fromJson(const {
        'text': 'x',
        'role': 'assistant',
        'lowStockItemsPayload': [
          {'name': 'Cannula', 'stock': 4},
        ],
      });
      expect(legacy.itemsPayload, hasLength(1));
      expect(legacy.itemsPayload!.first['name'], 'Cannula');
    });

    test('an unknown role or status falls back rather than throwing', () {
      final odd = ChatMessage.fromJson(const {
        'text': 'x',
        'role': 'system',
        'status': 'exploded',
      });
      expect(odd.role, ChatRole.assistant);
      expect(odd.status, ChatStatus.complete);
    });
  });

  group('ChatMessage.copyWith', () {
    test('keeps identity and timestamp while replacing content', () {
      // Streaming replaces the message on every delta; if the id changed the
      // list would rebuild the widget instead of updating it.
      final first = ChatMessage(
        text: 'Hel',
        role: ChatRole.assistant,
        status: ChatStatus.streaming,
      );
      final next = first.copyWith(text: 'Hello', status: ChatStatus.complete);

      expect(next.id, first.id);
      expect(next.createdAt, first.createdAt);
      expect(next.text, 'Hello');
      expect(next.status, ChatStatus.complete);
      expect(next.isStreaming, isFalse);
    });
  });

  group('ChatMessage helpers', () {
    test('report the role and lifecycle', () {
      final user = ChatMessage(text: 'hi', role: ChatRole.user);
      expect(user.isUser, isTrue);

      final failed = ChatMessage(
        text: '',
        role: ChatRole.assistant,
        status: ChatStatus.failed,
      );
      expect(failed.hasFailed, isTrue);
      expect(failed.isUser, isFalse);
    });
  });
}
