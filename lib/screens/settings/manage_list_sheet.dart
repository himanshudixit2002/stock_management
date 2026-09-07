/// The "manage this list" editor behind Categories, Companies, Sub-categories
/// and Locations.
///
/// Extracted from the Settings screen because it has a second, independent
/// entry point: Stock In, Stock Transfer and Stock Adjustment all send someone
/// here when a product has no locations to pick from. That path used to depend
/// on the whole 3000-line Settings screen being built just to open a sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/responsive.dart';

String _newLabel(String addLabel) {
  if (addLabel.isEmpty) return 'New item';
  final s = addLabel.trim();
  return 'New ${s[0].toUpperCase()}${s.length > 1 ? s.substring(1) : ''} name';
}

String _listHeading(String addLabel, int count) {
  if (addLabel.isEmpty) return 'Current list ($count)';
  final s = addLabel.trim().toLowerCase();
  final plural = s == 'company'
      ? 'companies'
      : s == 'location'
      ? 'locations'
      : s == 'category'
      ? 'categories'
      : s.endsWith('s')
      ? '${s}es'
      : '${s}s';
  final cap = '${plural[0].toUpperCase()}${plural.substring(1)}';
  return 'Your $cap ($count)';
}

void showManageListSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required List<String> Function() getItems,
  required Future<bool> Function(String) onAdd,
  required Future<bool> Function(String) onRemove,
  Future<bool> Function(String oldName, String newName)? onRename,
  String addLabel = '',
}) {
  final textCtrl = TextEditingController();
  final focusNode = FocusNode();
  final sheetController = DraggableScrollableController();

  showModalBottomSheet<void>(
    context: context,
    constraints: Responsive.sheetConstraints(context),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => MediaQuery.removeViewInsets(
      removeBottom: true,
      context: sheetCtx,
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final items = getItems();
          String? errorText;

          Future<void> handleAdd() async {
            final name = textCtrl.text.trim();
            if (name.isEmpty) return;
            final ok = await onAdd(name);
            if (ok) {
              textCtrl.clear();
              HapticFeedback.lightImpact();
              setSheetState(() {});
              focusNode.requestFocus();
            } else {
              setSheetState(() => errorText = '\'$name\' already exists');
            }
          }

          return DraggableScrollableSheet(
            controller: sheetController,
            initialChildSize: 0.7,
            minChildSize: 0.35,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.7, 0.95],
            builder: (sheetContext, scrollController) {
              final keyboardHeight = MediaQuery.viewInsetsOf(
                sheetCtx,
              ).bottom;
              if (keyboardHeight > 0 && sheetController.isAttached) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (sheetController.isAttached &&
                      sheetController.size < 0.9) {
                    sheetController.animateTo(
                      0.95,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 2),
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppTheme.dividerStrongC(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPri(context),
                                  ),
                                ),
                                Text(
                                  '${items.length} item${items.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            iconSize: 20,
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _newLabel(addLabel),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: textCtrl,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter name',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        8,
                                        10,
                                      ),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    onChanged: (_) {
                                      if (errorText != null) {
                                        setSheetState(() => errorText = null);
                                      }
                                    },
                                    onSubmitted: (_) => handleAdd(),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 6,
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  child: OutlinedButton(
                                    onPressed: handleAdd,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          8,
                                        ),
                                      ),
                                    ),
                                    child: const Text('Add'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (errorText != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                errorText!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _listHeading(addLabel, items.length),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 40,
                                    color: AppTheme.emptyIcon(
                                      context,
                                    ).withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No items yet',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Add one above',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSec(
                                        context,
                                      ).withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: keyboardHeight + 16,
                              ),
                              itemCount: items.length,
                              itemBuilder: (_, i) {
                                final renameCb = onRename;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ManageListItem(
                                    name: items[i],
                                    onEdit: renameCb != null
                                        ? () => _showRenameSheet(
                                            ctx,
                                            title: title,
                                            currentName: items[i],
                                            onRename: renameCb,
                                            onSuccess: () {
                                              setSheetState(() {});
                                            },
                                          )
                                        : null,
                                    onRemove: () async {
                                      final confirmed =
                                          await _showRemoveConfirmation(
                                            ctx,
                                            items[i],
                                          );
                                      if (confirmed) {
                                        await onRemove(items[i]);
                                        HapticFeedback.lightImpact();
                                        setSheetState(() {});
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  ).whenComplete(() {
    textCtrl.dispose();
    focusNode.dispose();
    // The sheet controller was created alongside the other two and never
    // released, so every visit to this sheet leaked one.
    sheetController.dispose();
  });
}

Future<void> _showRenameSheet(
  BuildContext context, {
  required String title,
  required String currentName,
  required Future<bool> Function(String oldName, String newName) onRename,
  required VoidCallback onSuccess,
}) async {
  final nameCtrl = TextEditingController(text: currentName);
  nameCtrl.selection = TextSelection(
    baseOffset: 0,
    extentOffset: currentName.length,
  );
  String? errorText;
  var isLoading = false;

  await showModalBottomSheet<void>(
    context: context,
    constraints: Responsive.sheetConstraints(context),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Rename',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPri(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'New name will update everywhere (products, transactions).',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  enabled: !isLoading,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: currentName,
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) async {
                    if (isLoading) return;
                    final newName = nameCtrl.text.trim();
                    if (newName.isEmpty) {
                      setState(() => errorText = 'Enter a name');
                      return;
                    }
                    if (newName == currentName) {
                      Navigator.pop(ctx);
                      return;
                    }
                    setState(() {
                      errorText = null;
                      isLoading = true;
                    });
                    final ok = await onRename(currentName, newName);
                    if (!ctx.mounted) return;
                    setState(() => isLoading = false);
                    if (ok) {
                      Navigator.pop(ctx);
                      onSuccess();
                    } else {
                      final msg =
                          context.read<SettingsProvider>().errorMessage ??
                          'Name already exists or rename failed.';
                      setState(() => errorText = msg);
                    }
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: AppTheme.dividerStrongC(context),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final newName = nameCtrl.text.trim();
                                if (newName.isEmpty) {
                                  setState(() => errorText = 'Enter a name');
                                  return;
                                }
                                if (newName == currentName) {
                                  Navigator.pop(ctx);
                                  return;
                                }
                                setState(() {
                                  errorText = null;
                                  isLoading = true;
                                });
                                final ok = await onRename(
                                  currentName,
                                  newName,
                                );
                                if (!ctx.mounted) return;
                                setState(() => isLoading = false);
                                if (ok) {
                                  Navigator.pop(ctx);
                                  onSuccess();
                                } else {
                                  final msg =
                                      context
                                          .read<SettingsProvider>()
                                          .errorMessage ??
                                      'Name already exists or rename failed.';
                                  setState(() => errorText = msg);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primaryColor,
                                ),
                              )
                            : const Text('Rename'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).whenComplete(nameCtrl.dispose);
}

Future<bool> _showRemoveConfirmation(
  BuildContext context,
  String itemName,
) async {
  return await showModalBottomSheet<bool>(
        context: context,
        constraints: Responsive.sheetConstraints(context),
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.dangerColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Remove "$itemName"?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Existing products with this value won\'t be affected.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSec(context),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppTheme.dividerStrongC(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppTheme.textSec(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.dangerColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
}

class _ManageListItem extends StatelessWidget {
  final String name;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  const _ManageListItem({
    required this.name,
    this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPri(context),
              ),
            ),
          ),
          if (onEdit != null)
            Material(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    color: AppTheme.primaryColor,
                    size: 16,
                  ),
                ),
              ),
            ),
          if (onEdit != null) const SizedBox(width: 8),
          Material(
            color: AppTheme.dangerColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  color: AppTheme.dangerColor,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The three product-attribute lists
// -----------------------------------------------------------------------------

/// The action ids a settings route may carry to open one of these directly.
class ManageListAction {
  ManageListAction._();

  static const String companies = 'companies';
  static const String sizes = 'sizes';
  static const String locations = 'locations';

  static const List<String> all = [companies, sizes, locations];
}

/// Opens the editor named by [action], or does nothing for an unknown one.
///
/// Named openers rather than four call sites passing the same eight closures:
/// the Locations editor is reachable from Settings *and* from Stock In, Stock
/// Transfer and Stock Adjustment, and those copies had already drifted — the
/// deep-linked one skipped the product refresh a rename needs, so renaming a
/// location from a stock screen left every product still showing the old name
/// until the next reload.
void showManageListAction(BuildContext context, String action) {
  switch (action) {
    case ManageListAction.companies:
      showManageCompaniesSheet(context);
    case ManageListAction.sizes:
      showManageSizesSheet(context);
    case ManageListAction.locations:
      showManageLocationsSheet(context);
  }
}

void showManageCompaniesSheet(BuildContext context) => showManageListSheet(
  context,
  title: 'Companies',
  icon: Icons.business_rounded,
  getItems: () => context.read<SettingsProvider>().companies,
  onAdd: (name) => context.read<SettingsProvider>().addCompany(name),
  onRemove: (name) => context.read<SettingsProvider>().removeCompany(name),
  onRename: (oldName, newName) =>
      _renameThenRefresh(context, (s) => s.renameCompany(oldName, newName)),
  addLabel: 'company',
);

void showManageSizesSheet(BuildContext context) => showManageListSheet(
  context,
  title: 'Sub-categories',
  icon: Icons.label_rounded,
  getItems: () => context.read<SettingsProvider>().sizes,
  onAdd: (name) => context.read<SettingsProvider>().addSize(name),
  onRemove: (name) => context.read<SettingsProvider>().removeSize(name),
  onRename: (oldName, newName) =>
      _renameThenRefresh(context, (s) => s.renameSize(oldName, newName)),
  addLabel: 'sub-category',
);

void showManageLocationsSheet(BuildContext context) => showManageListSheet(
  context,
  title: 'Locations',
  icon: Icons.location_on_rounded,
  getItems: () => context.read<SettingsProvider>().locations,
  onAdd: (name) => context.read<SettingsProvider>().addLocation(name),
  onRemove: (name) => context.read<SettingsProvider>().removeLocation(name),
  onRename: (oldName, newName) =>
      _renameThenRefresh(context, (s) => s.renameLocation(oldName, newName)),
  addLabel: 'location',
);

/// A rename rewrites the value on every matching product, so the in-memory
/// product list has to be re-read or the old name lingers in the UI.
Future<bool> _renameThenRefresh(
  BuildContext context,
  Future<bool> Function(SettingsProvider) rename,
) async {
  final ok = await rename(context.read<SettingsProvider>());
  if (ok && context.mounted) {
    context.read<ProductProvider>().refreshProducts();
  }
  return ok;
}
