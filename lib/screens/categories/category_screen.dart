import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/category_model.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  final Set<String> _expanded = {};

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
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final productCounts = productProvider.productCountByCategory;
    final topLevel = categoryProvider.topLevelCategories;

    final filteredTopLevel = _searchQuery.isEmpty
        ? topLevel
        : topLevel.where((c) {
            if (c.name.toLowerCase().contains(_searchQuery)) return true;
            final subs = categoryProvider.getSubcategoriesOf(c.id);
            return subs.any((s) => s.name.toLowerCase().contains(_searchQuery));
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.category_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Categories (${topLevel.length}${categoryProvider.categories.length > topLevel.length ? ' + ${categoryProvider.categories.length - topLevel.length} sub' : ''})'),
          ],
        ),
      ),
      body: categoryProvider.isLoading
          ? const ShimmerLoading(itemCount: 5, layout: ShimmerLayout.listTile)
          : topLevel.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.category_outlined,
                  title: 'No Categories',
                  subtitle: 'Create categories to organize your products',
                  buttonText: isAdmin ? 'Add Category' : null,
                  onButtonPressed: isAdmin
                      ? () => _showAddEditDialog(context)
                      : null,
                )
              : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
                  child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 12, Responsive.horizontalPadding(context), 8),
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
                          fillColor: AppTheme.inputFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.inputBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.inputBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppTheme.primaryColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredTopLevel.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text('No categories match "$_searchQuery"',
                                      style: TextStyle(fontSize: 15, color: Colors.grey[600])),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                              itemCount: filteredTopLevel.length,
                              itemBuilder: (context, index) {
                                final cat = filteredTopLevel[index];
                                final subcats = categoryProvider.getSubcategoriesOf(cat.id);
                                final count = productCounts[cat.name] ?? 0;
                                final isExpanded = _expanded.contains(cat.id);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        left: BorderSide(color: AppTheme.primaryColor, width: 4),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                            child: const Icon(Icons.category, color: AppTheme.primaryColor),
                                          ),
                                          title: Text(cat.name,
                                              style: const TextStyle(fontWeight: FontWeight.w600)),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (cat.description.isNotEmpty)
                                                Text(cat.description),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.inventory_2_outlined,
                                                      size: 13, color: AppTheme.textSecondary),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '$count product${count == 1 ? '' : 's'}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.textSecondary,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (subcats.isNotEmpty) ...[
                                                    const Text(' • ',
                                                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                                    Text(
                                                      '${subcats.length} sub',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.textSecondary,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (subcats.isNotEmpty)
                                                IconButton(
                                                  icon: AnimatedRotation(
                                                    turns: isExpanded ? 0.5 : 0,
                                                    duration: const Duration(milliseconds: 200),
                                                    child: const Icon(Icons.expand_more_rounded, size: 24),
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      if (isExpanded) {
                                                        _expanded.remove(cat.id);
                                                      } else {
                                                        _expanded.add(cat.id);
                                                      }
                                                    });
                                                  },
                                                ),
                                              if (isAdmin)
                                                PopupMenuButton<String>(
                                                  onSelected: (value) {
                                                    if (value == 'edit') {
                                                      _showAddEditDialog(context, category: cat);
                                                    } else if (value == 'delete') {
                                                      _confirmDelete(context, cat);
                                                    } else if (value == 'add_sub') {
                                                      _showAddEditDialog(context, parentCategory: cat);
                                                    }
                                                  },
                                                  itemBuilder: (_) => [
                                                    const PopupMenuItem(
                                                      value: 'add_sub',
                                                      child: Row(children: [
                                                        Icon(Icons.add_rounded, size: 20),
                                                        SizedBox(width: 8),
                                                        Text('Add Subcategory'),
                                                      ]),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Row(children: [
                                                        Icon(Icons.edit, size: 20),
                                                        SizedBox(width: 8),
                                                        Text('Edit'),
                                                      ]),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(children: [
                                                        Icon(Icons.delete, size: 20, color: AppTheme.dangerColor),
                                                        const SizedBox(width: 8),
                                                        Text('Delete', style: TextStyle(color: AppTheme.dangerColor)),
                                                      ]),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          onTap: subcats.isNotEmpty
                                              ? () => setState(() {
                                                    if (isExpanded) {
                                                      _expanded.remove(cat.id);
                                                    } else {
                                                      _expanded.add(cat.id);
                                                    }
                                                  })
                                              : null,
                                        ),
                                        // Subcategories
                                        AnimatedCrossFade(
                                          duration: const Duration(milliseconds: 200),
                                          crossFadeState: isExpanded
                                              ? CrossFadeState.showSecond
                                              : CrossFadeState.showFirst,
                                          firstChild: const SizedBox.shrink(),
                                          secondChild: Column(
                                            children: subcats.map((sub) {
                                              return Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[50],
                                                  border: Border(
                                                    top: BorderSide(color: AppTheme.dividerColor),
                                                  ),
                                                ),
                                                child: ListTile(
                                                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                                                  leading: Icon(Icons.subdirectory_arrow_right_rounded,
                                                      size: 20, color: AppTheme.indigoColor),
                                                  title: Text(sub.name,
                                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                                  subtitle: sub.description.isNotEmpty
                                                      ? Text(sub.description, style: const TextStyle(fontSize: 12))
                                                      : null,
                                                  trailing: isAdmin
                                                      ? PopupMenuButton<String>(
                                                          onSelected: (value) {
                                                            if (value == 'edit') {
                                                              _showAddEditDialog(context,
                                                                  category: sub, parentCategory: cat);
                                                            } else if (value == 'delete') {
                                                              _confirmDelete(context, sub);
                                                            }
                                                          },
                                                          itemBuilder: (_) => [
                                                            const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Row(children: [
                                                                Icon(Icons.edit, size: 20),
                                                                SizedBox(width: 8),
                                                                Text('Edit'),
                                                              ]),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'delete',
                                                              child: Row(children: [
                                                                Icon(Icons.delete, size: 20, color: AppTheme.dangerColor),
                                                                const SizedBox(width: 8),
                                                                Text('Delete',
                                                                    style: TextStyle(color: AppTheme.dangerColor)),
                                                              ]),
                                                            ),
                                                          ],
                                                        )
                                                      : null,
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                ),
                ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _showAddEditDialog(context),
              tooltip: 'Add Category',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showAddEditDialog(
    BuildContext context, {
    CategoryModel? category,
    CategoryModel? parentCategory,
  }) {
    final isSubcategory = parentCategory != null;
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(text: category?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final isEditing = category != null;

    final title = isEditing
        ? (category.isSubcategory ? 'Edit Subcategory' : 'Edit Category')
        : (isSubcategory ? 'Add Subcategory' : 'Add Category');

    int addedCount = 0;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<bool> doAdd({required bool closeAfter}) async {
            if (isSaving) return false;
            if (!formKey.currentState!.validate()) return false;
            setDialogState(() => isSaving = true);

            final user = dialogContext.read<AuthProvider>().currentUser;
            final categoryProvider = dialogContext.read<CategoryProvider>();
            bool success;

            if (isEditing) {
              success = await categoryProvider.updateCategory(
                category.copyWith(
                  name: nameController.text.trim(),
                  description: descController.text.trim(),
                  updatedBy: user?.uid ?? '',
                  updatedByName: user?.name ?? '',
                  updatedAt: DateTime.now(),
                ),
              );
            } else {
              success = await categoryProvider.addCategory(
                nameController.text.trim(),
                description: descController.text.trim(),
                userId: user?.uid ?? '',
                userName: user?.name ?? '',
                parentId: isSubcategory ? parentCategory.id : null,
                parentName: isSubcategory ? parentCategory.name : '',
              ) != null;
            }

            if (!dialogContext.mounted) return false;
            setDialogState(() => isSaving = false);

            if (success) {
              if (isSubcategory) {
                setState(() => _expanded.add(parentCategory.id));
              }
              if (closeAfter) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(isEditing
                        ? 'Updated!'
                        : addedCount > 0
                            ? '${addedCount + 1} subcategories added!'
                            : 'Added!'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              } else {
                addedCount++;
                final addedName = nameController.text.trim();
                nameController.clear();
                descController.clear();
                setDialogState(() {});
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('"${addedName.isEmpty ? 'Subcategory' : addedName}" added ($addedCount so far)'),
                    backgroundColor: AppTheme.successColor,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            } else {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(categoryProvider.errorMessage ?? 'Something went wrong'),
                  backgroundColor: AppTheme.dangerColor,
                ),
              );
            }
            return success;
          }

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (isSubcategory && !isEditing && addedCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$addedCount added',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.successColor,
                            fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSubcategory && !isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.subdirectory_arrow_right_rounded,
                              size: 18, color: AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text('Under: ${parentCategory.name}',
                              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '${isSubcategory ? "Subcategory" : "Category"} Name *',
                      prefixIcon: Icon(isSubcategory ? Icons.label_rounded : Icons.category),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                    onFieldSubmitted: isSubcategory && !isEditing
                        ? (_) => doAdd(closeAfter: false)
                        : null,
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
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (addedCount > 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('$addedCount subcategories added!'),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                  }
                },
                child: Text(addedCount > 0 ? 'Done' : 'Cancel'),
              ),
              if (isSubcategory && !isEditing)
                OutlinedButton(
                  onPressed: isSaving ? null : () => doAdd(closeAfter: false),
                  child: const Text('Add & Another'),
                ),
              ElevatedButton(
                onPressed: isSaving ? null : () => doAdd(closeAfter: true),
                child: isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
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
        .where((p) => p.categoryId == category.id || p.subcategoryId == category.id)
        .length;
    final subcatCount = category.isTopLevel
        ? context.read<CategoryProvider>().getSubcategoriesOf(category.id).length
        : 0;

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
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppTheme.dangerColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Delete ${category.isSubcategory ? "Subcategory" : "Category"}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${category.name}"?'),
            if (subcatCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$subcatCount subcategory(ies) will also be deleted.',
                        style: const TextStyle(fontSize: 13, color: AppTheme.warningColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (productsUsingCategory > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.dangerColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$productsUsingCategory product(s) use this. Cannot delete until products are moved.',
                        style: const TextStyle(fontSize: 13, color: AppTheme.dangerColor),
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
                      final provider = context.read<CategoryProvider>();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success
                              ? 'Deleted!'
                              : provider.errorMessage ?? 'Cannot delete'),
                          backgroundColor: success ? AppTheme.successColor : AppTheme.dangerColor,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: isDeleting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Delete'),
          ),
        ],
      ),
      ),
    );
  }
}
