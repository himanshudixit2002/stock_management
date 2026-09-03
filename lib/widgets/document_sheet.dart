import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../utils/date_formats.dart';
import '../utils/responsive.dart';

/// Shows any Firestore document as a readable key/value sheet.
///
/// The console's job is "read everything", and no hand-written detail card can
/// keep up with twenty-odd collections whose shapes keep growing — a field
/// added to a model would silently stop being visible. Rendering the raw map
/// means the sheet is always complete by construction.
Future<void> showDocumentSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Map<String, dynamic> data,
}) {
  return showResponsiveBottomSheet(
    context: context,
    maxHeightFactor: 0.85,
    builder: (_) => _DocumentSheet(
      title: title,
      subtitle: subtitle,
      data: data,
    ),
  );
}

class _DocumentSheet extends StatelessWidget {
  const _DocumentSheet({
    required this.title,
    required this.subtitle,
    required this.data,
  });

  final String title;
  final String? subtitle;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final keys = data.keys.toList()..sort();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.dividerStrongC(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSec(context)),
                        ),
                    ],
                  ),
                ),
                _CopyIdButton(id: data['id']?.toString() ?? ''),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              shrinkWrap: true,
              itemCount: keys.length,
              separatorBuilder: (_, _) => Divider(
                height: 16,
                color: AppTheme.dividerC(context),
              ),
              itemBuilder: (_, i) =>
                  _FieldRow(label: keys[i], value: data[keys[i]]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copies the document id, confirming inside the sheet.
///
/// A snackbar would render *behind* the modal sheet, so the confirmation was
/// invisible exactly when it was needed.
class _CopyIdButton extends StatefulWidget {
  const _CopyIdButton({required this.id});

  final String id;

  @override
  State<_CopyIdButton> createState() => _CopyIdButtonState();
}

class _CopyIdButtonState extends State<_CopyIdButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    if (widget.id.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: _copied ? 'Copied' : 'Copy document id',
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 18,
        color: _copied ? AppTheme.successColor : null,
      ),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.id));
        if (!mounted) return;
        setState(() => _copied = true);
      },
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value, this.depth = 0});

  final String label;
  final dynamic value;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final nested = _nestedEntries(value);
    if (nested != null) {
      return Padding(
        padding: EdgeInsets.only(left: depth * 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(height: 6),
            if (nested.isEmpty)
              Text(
                'empty',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMute(context),
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (final entry in nested)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FieldRow(
                    label: entry.key,
                    value: entry.value,
                    depth: depth + 1,
                  ),
                ),
          ],
        ),
      );
    }

    // Proportional rather than a fixed 140px label column: at 320dp that was
    // half the sheet, and nested rows subtract another 12px per level on top.
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.textSec(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SelectableText(
              formatDocumentValue(value),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// The children to render inline, or null when [value] is a leaf.
  static List<MapEntry<String, dynamic>>? _nestedEntries(dynamic value) {
    if (value is Map) {
      return [
        for (final e in value.entries) MapEntry(e.key.toString(), e.value),
      ]..sort((a, b) => a.key.compareTo(b.key));
    }
    // A list of scalars reads better as one line; a list of maps does not.
    if (value is List && value.any((e) => e is Map || e is List)) {
      return [
        for (var i = 0; i < value.length; i++) MapEntry('[$i]', value[i]),
      ];
    }
    return null;
  }
}

/// A single Firestore value as display text.
///
/// Timestamps are the reason this exists: printed raw they read as
/// `Timestamp(seconds=…)`, which tells a reader nothing.
String formatDocumentValue(dynamic value) {
  if (value == null) return '—';
  if (value is Timestamp) return AppDates.dayTime.format(value.toDate());
  if (value is DateTime) return AppDates.dayTime.format(value);
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is DocumentReference) return value.path;
  if (value is GeoPoint) return '${value.latitude}, ${value.longitude}';
  if (value is List) {
    if (value.isEmpty) return '—';
    return value.map(formatDocumentValue).join(', ');
  }
  final text = value.toString();
  return text.isEmpty ? '—' : text;
}
