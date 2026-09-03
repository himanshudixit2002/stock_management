import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/promo_config_model.dart';

/// Reads and writes `publicConfig/promo`.
///
/// The read side runs **signed out** — it feeds the register and login banners
/// — which is why the document lives in a world-readable collection rather than
/// under `metadata`, whose read rule requires authentication.
class PromoService {
  PromoService({FirebaseFirestore? firestore})
    : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  static const String docId = 'promo';

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('publicConfig').doc(docId);

  /// The current offer, or null if there is none configured or it cannot be
  /// read.
  ///
  /// Never throws: a promotion is decoration, and a config problem must not
  /// stop anyone signing up.
  Future<PromoConfig?> fetch() async {
    try {
      final snap = await _doc.get();
      if (!snap.exists) return null;
      return PromoConfig.fromMap(snap.data());
    } catch (_) {
      return null;
    }
  }

  Stream<PromoConfig?> watch() {
    return _doc
        .snapshots()
        .map((snap) => snap.exists ? PromoConfig.fromMap(snap.data()) : null)
        .handleError((_) {});
  }

  /// Platform admin only, per the security rules.
  Future<void> save(PromoConfig config) => _doc.set(config.toMap());
}
