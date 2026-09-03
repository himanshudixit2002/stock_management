import 'package:flutter/foundation.dart';

import '../models/promo_config_model.dart';
import '../services/promo_service.dart';

/// The founding-member offer, for the signed-out screens and the console.
///
/// Deliberately failure-tolerant everywhere: [config] simply stays null when
/// the read fails, and the banner renders nothing. A promotion must never be
/// able to block a signup.
class PromoProvider extends ChangeNotifier {
  PromoProvider({PromoService? service})
    : _service = service ?? PromoService();

  final PromoService _service;

  PromoConfig? _config;
  bool _loaded = false;
  bool _loading = false;

  /// The current offer, or null when there is none or it could not be read.
  PromoConfig? get config => _config;

  /// True once a load has completed, successfully or not.
  bool get loaded => _loaded;

  /// The offer to actually show: null unless one is configured *and* enabled.
  PromoConfig? get visibleConfig {
    final c = _config;
    return (c != null && c.enabled) ? c : null;
  }

  /// Loads the offer once. Safe to call from every screen that shows a banner.
  Future<void> load({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    try {
      _config = await _service.fetch();
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Writes the offer. Platform admin only — the rules enforce it.
  Future<bool> save(PromoConfig config) async {
    try {
      await _service.save(config);
      _config = config;
      _loaded = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void reset() {
    _config = null;
    _loaded = false;
    notifyListeners();
  }
}
