import 'package:cloud_firestore/cloud_firestore.dart';

/// Writes in-app feedback to `companies/{companyId}/feedback`.
///
/// This is intentionally minimal: one append-only document per submission,
/// company-scoped like every other tenant collection. A matching rule is in
/// `firestore.rules` (members may create; admins may read). If the deployed
/// rules predate that addition the write will fail and the caller falls back
/// to an email link.
class FeedbackService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String companyId) =>
      _firestore.collection('companies').doc(companyId).collection('feedback');

  /// Submits a feedback entry for [companyId]. Throws on failure so the caller
  /// can offer a fallback (e.g. mailto).
  Future<void> submit({
    required String companyId,
    required String message,
    required String category,
    required String userId,
    required String userName,
    required String userEmail,
  }) async {
    if (companyId.isEmpty) {
      throw StateError('No active company.');
    }
    await _collection(companyId).add({
      'message': message.trim(),
      'category': category,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'app',
    });
  }
}
