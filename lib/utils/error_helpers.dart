String friendlyError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
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
  if (msg.contains('quota') || msg.contains('limit')) {
    return 'Usage limit reached. Please try again later.';
  }
  return fallback;
}
