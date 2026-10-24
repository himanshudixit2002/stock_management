import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/plan_limits.dart';
import 'package:stock_management/utils/error_helpers.dart';

void main() {
  group('friendlyError keeps the app\'s own explanations', () {
    test('an Exception thrown with a sentence', () {
      expect(
        friendlyError(Exception('This category is in use by 3 products.')),
        'This category is in use by 3 products.',
      );
    });

    test('one that happens to contain a keyword', () {
      // "not found" used to turn this into "The requested item was not found."
      expect(
        friendlyError(Exception('Product not found for one of the held items.')),
        'Product not found for one of the held items.',
      );
    });

    test('a plan limit, whose message contains "limit"', () {
      const error = PlanLimitException(
        key: 'products',
        limit: 100,
        planLabel: 'Starter',
      );
      expect(friendlyError(error), error.message);
    });

    test('an ArgumentError phrased as a sentence', () {
      expect(
        friendlyError(ArgumentError('Please enter a valid phone number.')),
        'Please enter a valid phone number.',
      );
    });
  });

  group('friendlyError still translates platform errors', () {
    test('a Firestore permission error', () {
      expect(
        friendlyError(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
        "You don't have permission to perform this action.",
      );
    });

    test('a Firestore error wrapped in an Exception', () {
      expect(
        friendlyError(
          Exception('[cloud_firestore/unavailable] The service is down'),
        ),
        'Network error. Please check your connection and try again.',
      );
    });

    test('a developer-facing ArgumentError', () {
      expect(
        friendlyError(ArgumentError('quantity must be > 0'), fallback: 'X'),
        'X',
      );
    });

    test('anything else falls back', () {
      expect(friendlyError(StateError('boom'), fallback: 'X'), 'X');
    });
  });
}
