import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../config/plan_limits.dart';

/// A message fit to show a person for [error].
///
/// Messages the app wrote for people are shown as written: a plan cap, an
/// `Exception('...')` thrown with an explanation, an [ArgumentError] phrased
/// as a sentence. Only errors from the platform (Firestore codes, network
/// failures) are mapped to the generic texts below. Every error used to go
/// through the keyword match, so "This category is in use by 3 products" came
/// out as [fallback], and a plan cap — its message contains "limit" — read
/// "Usage limit reached. Please try again later."
String friendlyError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is PlanLimitException) return error.message;
  if (error is! FirebaseException) {
    final own = _ownMessage(error);
    if (own != null) return own;
  }

  final msg = error.toString().toLowerCase();
  if (msg.contains('permission') || msg.contains('denied')) {
    return 'You don\'t have permission to perform this action.';
  }
  if (msg.contains('not-found') || msg.contains('not found')) {
    return 'The requested item was not found.';
  }
  if (msg.contains('already-exists') || msg.contains('duplicate')) {
    return 'This item already exists.';
  }
  if (msg.contains('network') ||
      msg.contains('unavailable') ||
      msg.contains('timeout')) {
    return 'Network error. Please check your connection and try again.';
  }
  if (msg.contains('quota') || msg.contains('resource-exhausted')) {
    return 'Usage limit reached. Please try again later.';
  }
  return fallback;
}

/// The text of an error the app raised for a person to read, or null.
String? _ownMessage(Object error) {
  String? text;
  if (error is ArgumentError && error.message is String) {
    text = error.message as String;
    // Only sentences: `ArgumentError('quantity must be > 0')` is for
    // developers, `ArgumentError('Please enter a valid phone number.')` is not.
    if (!_isSentence(text)) return null;
  } else if (error is Exception) {
    final raw = error.toString();
    if (!raw.startsWith('Exception: ')) return null;
    text = raw.substring('Exception: '.length);
  }
  if (text == null) return null;
  text = text.trim();
  if (text.isEmpty || _looksTechnical(text)) return null;
  return text;
}

bool _isSentence(String text) {
  final t = text.trim();
  return t.length > 1 &&
      t[0] == t[0].toUpperCase() &&
      t[0] != t[0].toLowerCase() &&
      (t.endsWith('.') || t.endsWith('!') || t.endsWith('?'));
}

/// A wrapped platform error, e.g. `Exception('$e')` around a Firestore one.
bool _looksTechnical(String text) {
  final lower = text.toLowerCase();
  return lower.contains('[cloud_firestore/') ||
      lower.contains('[firebase_auth/') ||
      lower.contains('firebaseexception') ||
      lower.contains('platformexception') ||
      lower.contains('instance of ');
}
