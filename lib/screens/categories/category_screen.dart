import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/category_model.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/success_overlay.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/permissions.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = value.trim().toLowerCase();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final productProvider = context.watch<ProductProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final canManageCategories =
        user?.hasPermission(AppPermissions.manageCategories) ?? false;
    final productCounts = productProvider.productCountByCategory;
    final categories = categoryProvider.categories;

    final filtered = _searchQuery.isEmpty
        ? categories
        : categories
              .where((c) => c.name.toLowerCase().contains(_searchQuery))
              .toList();

    return AppScreenScaffold(
      icon: Icons.category_rounded,
      title: 'Categories (${categories.length})',
      shimmerLayout: ShimmerLayout.listTile,
      isLoading: categoryProvider.isLoading,
      isEmpty: categories.isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.category_outlined,
        title: 'No Categories',
        subtitle: 'Create categories to organize your products',
        buttonText: canManageCategories ? 'Add Category' : null,
        onButtonPressed: canManageCategories
            ? () => _showAddEditDialog(context)
            : null,
      ),
      floatingActionButton: canManageCategories
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditDialog(context),
              tooltip: 'Add Category',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              12,
              Responsive.horizontalPadding(context),
              8,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search categories...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.inputBorder(context),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.inputBorder(context),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? NotFoundState(
                    title: 'No Matches',
                    message: 'No categories match "$_searchQuery"',
                  )
                : RefreshIndicator(
                    color: AppTheme.primaryColor,
                    onRefresh: () async {
                      categoryProvider.initialize(
                        companyId: user?.companyId ?? '',
                      );
                      await Future.delayed(
                        const Duration(milliseconds: 500),
                      );
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.all(
                        Responsive.horizontalPadding(context),
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final cat = filtered[index];
                        final count = productCounts[cat.name] ?? 0;

                        return AnimatedListItem(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              borderRadius: 14,
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: AppTheme.primaryColor,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.primaryColor
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.category,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  title: Text(
                                    cat.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (cat.description.isNotEmpty)
                                        Text(cat.description),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 13,
                                            color: AppTheme.textSec(context),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$count product${count == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSec(context),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: canManageCategories
                                      ? PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _showAddEditDialog(
                                                context,
                                                category: cat,
                                              );
                                            } else if (value == 'delete') {
                                              _confirmDelete(context, cat);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete,
                                                    size: 20,
                                                    color: AppTheme.dangerColor,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                      color:
                                                          AppTheme.dangerColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog(BuildContext context, {CategoryModel? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(
      text: category?.description ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final isEditing = category != null;
    final categoryProvider = context.read<CategoryProvider>();

    final title = isEditing ? 'Edit Category' : 'Add Category';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(title),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Category Name *',
                      prefixIcon: Icon(Icons.category),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      final dupError = categoryProvider.validateCategoryName(
                        value,
                        excludeId: isEditing ? category.id : null,
                      );
                      if (dupError != null) return dupError;
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSaving = true);

                        final user = dialogContext
                            .read<AuthProvider>()
                            .currentUser;
                        final catProvider = dialogContext
                            .read<CategoryProvider>();
                        bool success;

                        if (isEditing) {
                          success = await catProvider.updateCategory(
                            category.copyWith(
                              name: nameController.text.trim(),
                              description: descController.text.trim(),
                              updatedBy: user?.uid ?? '',
                              updatedByName: user?.name ?? '',
                              updatedAt: DateTime.now(),
                            ),
                          );
                        } else {
                          success =
                              await catProvider.addCategory(
                                nameController.text.trim(),
                                description: descController.text.trim(),
                                userId: user?.uid ?? '',
                                userName: user?.name ?? '',
                              ) !=
                              null;
                        }

                        if (!dialogContext.mounted) return;
                        setDialogState(() => isSaving = false);

                        if (success) {
                          if (isEditing) {
                            dialogContext
                                .read<ProductProvider>()
                                .refreshProducts();
                          }
                          Navigator.pop(dialogContext);
                          showSuccessOverlay(
                            context,
                            message: isEditing ? 'Updated!' : 'Added!',
                            popAfter: false,
                          );
                        } else {
                          showErrorSnackBar(
                            dialogContext,
                            catProvider.errorMessage ?? 'Something went wrong',
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, CategoryModel category) {
    final productProvider = context.read<ProductProvider>();
    final productsUsingCategory = productProvider.allProducts
        .where((p) => p.categoryId == category.id)
        .length;

    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppTheme.dangerColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Delete Category'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete "${category.name}"?'),
              if (productsUsingCategory > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.dangerColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.dangerColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$productsUsingCategory product(s) use this. Cannot delete until products are moved.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.dangerColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setDialogState(() => isDeleting = true);
                      HapticFeedback.heavyImpact();
                      final success = await context
                          .read<CategoryProvider>()
                          .deleteCategory(category.id);

                      if (context.mounted) {
                        Navigator.pop(context);
                        if (success) {
                          showSuccessOverlay(
                            context,
                            message: 'Deleted!',
                            popAfter: false,
                          );
                        } else {
                          final provider = context.read<CategoryProvider>();
                          showErrorSnackBar(
                            context,
                            provider.errorMessage ?? 'Cannot delete',
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerColor,
              ),
              child: isDeleting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.surface(context),
                      ),
                    )
                  : const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
