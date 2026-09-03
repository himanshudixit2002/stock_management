import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A form field that opens a picker instead of a keyboard.
///
/// Each stock form hand-built its own "Tap to select a product" pseudo-field —
/// six near-identical blocks with slightly different padding, borders and empty
/// copy. This is the shared one; back it with the existing
/// `showProductPicker` / `showSearchablePicker` sheets.
///
/// It renders an error state so a picker field can participate in form
/// validation, which the hand-built versions could not.
class EntityPickerField extends StatelessWidget {
  const EntityPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
    this.placeholder = 'Tap to select',
    this.detail,
    this.errorText,
    this.accent,
    this.onClear,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// The chosen entity's name, or null when nothing is selected yet.
  final String? value;

  final String placeholder;

  /// A secondary line — stock on hand, a code, a balance.
  final String? detail;

  final String? errorText;
  final Color? accent;
  final VoidCallback? onClear;
  final bool enabled;

  bool get _hasValue => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.primary(context);
    final hasError = errorText != null;
    final borderColor = hasError
        ? AppTheme.danger(context)
        : (_hasValue ? color.withValues(alpha: 0.45) : AppTheme.inputBorder(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppTheme.spacingSM),
        // Material + InkWell rather than a GestureDetector so the field gives
        // the same ripple as every other tappable surface.
        Material(
          color: AppTheme.inputFill(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLG,
                vertical: AppTheme.spacingMD,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: borderColor,
                  width: _hasValue || hasError ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.tint(context, color),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXS),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 17, color: color),
                  ),
                  const SizedBox(width: AppTheme.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _hasValue ? value! : placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _hasValue
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: AppTheme.textMute(context),
                                    ),
                        ),
                        if (_hasValue && detail != null)
                          Text(
                            detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (_hasValue && onClear != null && enabled)
                    IconButton(
                      tooltip: 'Clear selection',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onClear,
                    )
                  else
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: AppTheme.iconMute(context),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.danger(context),
            ),
          ),
        ],
      ],
    );
  }
}
