import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/services/rag_api_service.dart';

void main() {
  /// The assistant used to answer every failure with "I couldn't reach the
  /// assistant", which reads as a problem with the user's connection. The
  /// failure that actually took it down was a 500 from Cloud Run whose body
  /// said billing was disabled for the project — nothing to do with the device,
  /// and invisible to anyone without access to the Cloud Run logs.
  group('failureMessageFor', () {
    test('no response at all blames the connection, because that is the case', () {
      final message = RagApiService.failureMessageFor(null);
      expect(message, contains('connection'));
    });

    test('a server error says it is not the user', () {
      for (final status in [500, 502, 503, 504]) {
        final message = RagApiService.failureMessageFor(status);
        expect(message, contains('not your'), reason: '$status');
        expect(message, contains('unavailable'), reason: '$status');
      }
    });

    test('an auth failure points at workspace access, not the network', () {
      for (final status in [401, 403]) {
        final message = RagApiService.failureMessageFor(status);
        expect(message.toLowerCase(), contains('access'), reason: '$status');
        expect(message, isNot(contains('connection')), reason: '$status');
      }
    });

    test('throttling asks the user to wait rather than to check anything', () {
      expect(
        RagApiService.failureMessageFor(429),
        contains('moment'),
      );
    });

    test('any other status is reported with its number', () {
      // A 404 or a 422 is a bug worth reporting precisely; inventing a friendly
      // explanation for it would hide the only clue.
      expect(RagApiService.failureMessageFor(404), contains('404'));
      expect(RagApiService.failureMessageFor(422), contains('422'));
    });

    test('every message is a complete sentence a user could act on', () {
      for (final status in [null, 401, 403, 429, 404, 500, 503]) {
        final message = RagApiService.failureMessageFor(status);
        expect(message.trim(), isNotEmpty, reason: '$status');
        expect(message.trim(), endsWith('.'), reason: '$status');
        // The interpolation bug this file also guards against: a literal
        // "$status" in the output means the escape was written into the string.
        expect(message, isNot(contains(r'$status')), reason: '$status');
      }
    });
  });

  group('isRetryableStatus', () {
    test('server errors and throttling are worth a second attempt', () {
      expect(RagApiService.isRetryableStatus(500), isTrue);
      expect(RagApiService.isRetryableStatus(503), isTrue);
      expect(RagApiService.isRetryableStatus(429), isTrue);
    });

    test('a refusal is not', () {
      // Retrying a 401 makes the user wait 800ms longer to read the same thing.
      expect(RagApiService.isRetryableStatus(401), isFalse);
      expect(RagApiService.isRetryableStatus(403), isFalse);
      expect(RagApiService.isRetryableStatus(404), isFalse);
      expect(RagApiService.isRetryableStatus(422), isFalse);
    });
  });

  group('RagResponse', () {
    test('an ordinary answer is not marked failed', () {
      const response = RagResponse('You have 12 units left.', null);
      expect(response.failed, isFalse);
    });

    test('a failure carries the flag the chat screen renders on', () {
      final response = RagResponse(
        RagApiService.failureMessageFor(500),
        null,
        failed: true,
      );
      expect(response.failed, isTrue);
    });
  });
}
