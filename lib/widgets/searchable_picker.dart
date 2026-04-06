import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';

class PickerItem {
  final String value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final bool isAction;

  const PickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.isAction = false,
  });
}

Future<String?> showSearchablePicker({
  required BuildContext context,
  required List<PickerItem> items,
  String? selectedValue,
  String title = 'Select',
  String searchHint = 'Type to narrow list',
  String? addNewLabel,
  String? addNewValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    constraints: Responsive.sheetConstraints(context),
    isScrollControlled: true,
    backgroundColor: AppTheme.surface(context),
    transitionAnimationController: AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 300),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      String search = '';
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final selectableItems = items.where((item) => !item.isAction).toList();
          final filtered = search.isEmpty
              ? selectableItems
              : selectableItems.where((item) {
                  final q = search.toLowerCase();
                  if (item.label.toLowerCase().contains(q)) return true;
                  if (item.subtitle != null && item.subtitle!.toLowerCase().contains(q)) return true;
                  return false;
                }).toList();

          final mq = MediaQuery.of(ctx);
          final keyboardHeight = mq.viewInsets.bottom;
          final maxHeight = mq.size.height * 0.85;

          return Padding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- pinned header ---
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.textSec(ctx).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(ctx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap one or narrow the list below.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSec(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Narrow list',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSec(ctx),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: searchHint,
                              prefixIcon: const Icon(
                                Icons.filter_list_rounded,
                                size: 18,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppTheme.inputBorder(ctx),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppTheme.primaryColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (v) => setSheetState(() => search = v),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- scrollable list ---
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No results',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSec(ctx),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final isSelected = item.value == selectedValue;
                              return ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                leading: item.icon != null
                                    ? Icon(
                                        item.icon,
                                        size: 20,
                                        color: item.iconColor ??
                                            AppTheme.textSec(ctx),
                                      )
                                    : null,
                                title: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: item.subtitle != null
                                    ? Text(
                                        item.subtitle!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(ctx),
                                        ),
                                      )
                                    : null,
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primaryColor,
                                        size: 20,
                                      )
                                    : null,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.pop(ctx, item.value);
                                },
                              );
                            },
                          ),
                  ),

                  // --- pinned "add new" button ---
                  if (addNewLabel != null && addNewValue != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface(ctx),
                      ),
                      child: SafeArea(
                        top: false,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, addNewValue),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(addNewLabel),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
