import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/serial_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/serial_provider.dart';
import '../../providers/service_job_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/glass_panel.dart';

/// One unit: where it is, what has happened to it, and what to do next.
class SerialDetailSheet extends StatefulWidget {
  const SerialDetailSheet({
    super.key,
    required this.serial,
    required this.userId,
    required this.userName,
  });

  final SerialModel serial;
  final String userId;
  final String userName;

  @override
  State<SerialDetailSheet> createState() => _SerialDetailSheetState();
}

class _SerialDetailSheetState extends State<SerialDetailSheet> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  late SerialModel _serial = widget.serial;

  /// Asks for an optional note. Returns null when dismissed, so an empty
  /// string can mean a deliberate "no note" rather than a cancel.
  Future<String?> _askForNote(SerialStatus status) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Mark as ${SerialModel.statusLabelOf(status).toLowerCase()}',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Reason or reference (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _move(SerialStatus status) async {
    final note = await _askForNote(status);
    if (note == null || !mounted) return;

    final provider = context.read<SerialProvider>();
    final ok = await provider.changeStatus(
      serial: _serial,
      status: status,
      userId: widget.userId,
      userName: widget.userName,
      note: note,
    );
    if (!mounted) return;
    if (!ok) {
      showErrorSnackBar(context, provider.errorMessage ?? 'Update failed.');
      return;
    }
    setState(() {
      _serial = _serial.withEvent(
        SerialEvent(
          action: SerialModel.statusLabelOf(status),
          note: note,
          userId: widget.userId,
          userName: widget.userName,
          at: DateTime.now(),
        ),
        status: status,
      );
    });
    showSuccessSnackBar(
      context,
      '${_serial.serialNumber} is now ${_serial.statusLabel.toLowerCase()}.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${_serial.serialNumber}?',
      message:
          'The unit and its history go for good. Scrapping it instead keeps '
          'the record.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<SerialProvider>();
    final ok = await provider.deleteSerial(_serial.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Deleted ${_serial.serialNumber}.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageSerials) ?? false,
    );
    final busy = context.watch<SerialProvider>().isBusy;
    final history = _serial.history.reversed.toList();

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _serial.serialNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (canManage)
                  IconButton(
                    onPressed: busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Delete',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _serial.productName,
              style: TextStyle(fontSize: 14, color: AppTheme.textSec(context)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Fact(label: 'Status', value: _serial.statusLabel),
                if (_serial.location.isNotEmpty)
                  _Fact(label: 'Location', value: _serial.location),
                if (_serial.batchNumber.isNotEmpty)
                  _Fact(label: 'Batch', value: _serial.batchNumber),
                if (_serial.warrantyUntil != null)
                  _Fact(
                    label: 'Warranty',
                    value: _serial.isUnderWarranty
                        ? 'Until ${DateFormat('dd MMM yyyy').format(_serial.warrantyUntil!)}'
                        : 'Expired',
                  ),
                if (_serial.referenceLabel.isNotEmpty)
                  _Fact(label: 'Last document', value: _serial.referenceLabel),
              ],
            ),
            if (canManage) ...[
              const SizedBox(height: 16),
              Text(
                'Move to',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in SerialStatus.values)
                    if (status != _serial.status)
                      OutlinedButton(
                        onPressed: busy ? null : () => _move(status),
                        child: Text(SerialModel.statusLabelOf(status)),
                      ),
                ],
              ),
            ],
            const Divider(height: 28),
            _serviceSection(context),
            Text(
              'History',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Text(
                'Nothing recorded yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSec(context),
                ),
              )
            else
              for (final event in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: AppTheme.primary(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.action,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              [
                                _dateFormat.format(event.at),
                                if (event.userName.isNotEmpty) event.userName,
                                if (event.note.isNotEmpty) event.note,
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Repairs raised against this unit, and the button that raises another.
///
/// Serial tracking exists so a unit can be identified after it is sold; this is
/// the sheet where somebody standing at a counter with the unit in their hand
/// actually needs that, so the service history lives here rather than only on
/// the service list.
extension _SerialServiceSection on _SerialDetailSheetState {
  Widget _serviceSection(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null ||
        !user.hasPermission(AppPermissions.viewServiceJobs)) {
      return const SizedBox.shrink();
    }
    final jobs = context.watch<ServiceJobProvider>().forSerial(_serial.id);
    final canRaise = user.hasPermission(AppPermissions.manageServiceJobs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Service history',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSec(context),
                ),
              ),
            ),
            if (canRaise)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.pushAppRoute(
                    AppRoutes.createServiceJob,
                    extra: _serial,
                  );
                },
                icon: const Icon(Icons.build_circle_rounded, size: 16),
                label: const Text('Raise a job'),
              ),
          ],
        ),
        if (jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'This unit has never been back.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSec(context),
              ),
            ),
          )
        else
          for (final job in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  context.pushAppRoute(
                    AppRoutes.serviceJobDetail,
                    extra: job.id,
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Icon(
                      job.isOpen
                          ? Icons.pending_actions_rounded
                          : Icons.check_circle_rounded,
                      size: 16,
                      color: job.isOpen
                          ? AppTheme.warningColor
                          : AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (job.jobNumber.isNotEmpty) job.jobNumber,
                          job.statusLabel,
                          if (job.faultDescription.isNotEmpty)
                            job.faultDescription,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const Divider(height: 28),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
