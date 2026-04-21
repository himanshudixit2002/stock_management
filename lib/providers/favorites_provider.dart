import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesProvider extends ChangeNotifier {
  final Set<String> _ids = {};
  String _storageKey = '';

  Set<String> get ids => Set.unmodifiable(_ids);

  bool isFavorite(String productId) => _ids.contains(productId);

  Future<void> initialize({required String companyId, required String uid}) async {
    _storageKey = 'favorites_${companyId}_$uid';
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey);
    _ids.clear();
    if (stored != null) _ids.addAll(stored);
    notifyListeners();
  }

  void toggle(String productId) {
    if (_ids.contains(productId)) {
      _ids.remove(productId);
    } else {
      _ids.add(productId);
    }
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    if (_storageKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _ids.toList());
  }

  void reset() {
    _ids.clear();
    _storageKey = '';
    notifyListeners();
  }
}
