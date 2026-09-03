import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/promo_config_model.dart';
import '../../providers/promo_provider.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/responsive.dart';

/// Edits the founding-member offer shown on the signed-out screens.
///
/// The counter is advisory — nothing counts signups atomically — so the
/// "claimed" figure is synced from the live workspace count on demand rather
/// than incremented at registration. The dialog says so, because copy that
/// implied a hard cutoff would be a claim the system cannot keep.
Future<bool> showPromoEditor(BuildContext context, PromoConfig current) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _PromoEditorDialog(current: current),
  );
  return result ?? false;
}

class _PromoEditorDialog extends StatefulWidget {
  const _PromoEditorDialog({required this.current});

  final PromoConfig current;

  @override
  State<_PromoEditorDialog> createState() => _PromoEditorDialogState();
}

class _PromoEditorDialogState extends State<_PromoEditorDialog> {
  late bool _enabled = widget.current.enabled;
  late final TextEditingController _headline = TextEditingController(
    text: widget.current.headline,
  );
  late final TextEditingController _subtext = TextEditingController(
    text: widget.current.subtext,
  );
  late final TextEditingController _fullHeadline = TextEditingController(
    text: widget.current.fullHeadline,
  );
  late final TextEditingController _fullSubtext = TextEditingController(
    text: widget.current.fullSubtext,
  );
  late final TextEditingController _cap = TextEditingController(
    text: widget.current.capCount.toString(),
  );
  late final TextEditingController _claimed = TextEditingController(
    text: widget.current.claimedCount.toString(),
  );

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _headline.dispose();
    _subtext.dispose();
    _fullHeadline.dispose();
    _fullSubtext.dispose();
    _cap.dispose();
    _claimed.dispose();
    super.dispose();
  }

  /// Fills the claimed count from the live workspace total.
  ///
  /// This is what keeps the number honest without a Cloud Function: one
  /// workspace is one signup, and the console already has the list.
  void _syncClaimed() {
    final count = context.read<SuperAdminProvider>().companies.length;
    _claimed.text = count.toString();
    setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final config = widget.current.copyWith(
      enabled: _enabled,
      headline: _headline.text.trim(),
      subtext: _subtext.text.trim(),
      fullHeadline: _fullHeadline.text.trim(),
      fullSubtext: _fullSubtext.text.trim(),
      capCount: int.tryParse(_cap.text.trim()) ?? widget.current.capCount,
      claimedCount: int.tryParse(_claimed.text.trim()) ?? 0,
    );
    final ok = await context.read<PromoProvider>().save(config);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save the offer. Check your connection and rules.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Founding-member offer'),
      content: SizedBox(
        width: Responsive.dialogMaxWidth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _saving ? null : (v) => setState(() => _enabled = v),
              title: const Text('Show on register and login'),
              subtitle: const Text(
                'Off hides the banner entirely for signed-out visitors.',
              ),
            ),
            const Divider(height: 24),
            TextField(
              controller: _headline,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Headline',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtext,
              enabled: !_saving,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Body',
                isDense: true,
              ),
            ),
            const Divider(height: 28),
            Text(
              'Once the cap is reached',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fullHeadline,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Headline when full',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullSubtext,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Body when full',
                isDense: true,
              ),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cap,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Cohort size',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _claimed,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Claimed',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _syncClaimed,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Sync from workspace count'),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppTheme.warningColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The cap is advisory. Nothing counts signups atomically, '
                      'and the security rules let a new workspace claim only '
                      'the MAX tier — so reaching the cap changes the banner '
                      'copy, not what a signup is granted. Keep the wording '
                      'away from a hard deadline.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.dangerColor,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save offer'),
        ),
      ],
    );
  }
}
