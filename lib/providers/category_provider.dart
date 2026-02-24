import 'dart:async';
import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class CategoryProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<CategoryModel> _categories = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _categoriesSubscription;

  List<CategoryModel> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _categoriesSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _categoriesSubscription = _databaseService.getCategories().listen(
      (categories) {
        _categories = categories;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(error, fallback: 'Could not load categories.');
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<CategoryModel?> addCategory(
    String name, {
    String description = '',
    String userId = '',
    String userName = '',
  }) async {
    try {
      _errorMessage = null;
      final now = DateTime.now();
      final category = CategoryModel(
        id: '',
        name: name,
        description: description,
        createdAt: now,
        updatedAt: now,
        createdBy: userId,
        createdByName: userName,
        updatedBy: userId,
        updatedByName: userName,
      );
      final newId = await _databaseService.addCategory(category);
      return category.copyWith(id: newId);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Category operation failed.');
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateCategory(CategoryModel category) async {
    try {
      _errorMessage = null;
      await _databaseService.updateCategory(category);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Category operation failed.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCategory(String categoryId) async {
    try {
      _errorMessage = null;
      await _databaseService.deleteCategory(categoryId);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Category operation failed.');
      notifyListeners();
      return false;
    }
  }

  CategoryModel? getCategoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Returns an error string if a category with the same name already exists,
  /// or null if the name is available. [excludeId] skips self when editing.
  String? validateCategoryName(String name, {String? excludeId}) {
    final normalizedName = name.trim().toLowerCase();
    final duplicate = _categories.any((c) =>
        c.id != excludeId && c.name.trim().toLowerCase() == normalizedName);
    if (duplicate) {
      return 'A category with this name already exists';
    }
    return null;
  }

  Map<String, CategoryModel> getCategoryNameMap() {
    final map = <String, CategoryModel>{};
    for (var category in _categories) {
      map[category.name.toLowerCase()] = category;
    }
    return map;
  }

  /// One-shot Firestore read to refresh categories. Useful after bulk writes
  /// where the stream listener may not have fired yet.
  Future<Map<String, CategoryModel>> fetchCategoryNameMap() async {
    final categories = await _databaseService.getCategoriesOnce();
    _categories = categories;
    notifyListeners();
    final map = <String, CategoryModel>{};
    for (var category in categories) {
      map[category.name.toLowerCase()] = category;
    }
    return map;
  }

  @override
  void dispose() {
    _categoriesSubscription?.cancel();
    super.dispose();
  }
}
