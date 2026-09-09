import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/requisition_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/requisition_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import 'requisition_list_screen.dart' show RequisitionCard;

/// One request: read it, decide it, or turn it into a purchase order.
class RequisitionDetailScreen extends StatelessWidget {
  const RequisitionDetailScreen({super.key, required this.requisitionId});

  final String requisitionId;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewRequisitions,
      featureName: 'Requisitions',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<RequisitionProvider>();
    // Always the live copy: a decision made from another device must not be
    // overwritten by the stale model this route was pushed with.
    final requisition = provider.byId(requisitionId);
    if (requisition == null) {
      return const NotFoundState(
        title: 'Requisition not found',
        message: 'It may have been deleted, or belongs to another workspace.',
      );
    }

    final user = context.read<AuthProvider>().currentUser;
    final canApprove =
        user?.hasPermission(AppPermissions.approveRequisitions) ?? false;
    final canEdit =
        (user?.hasPermission(AppPermissions.createRequisitions) ?? false) &&
        requisition.canEdit;
    final symbol = Money.symbolOf(context);

    return AppScreenScaffold(
      icon: Icons.assignment_rounded,
      title: requisition.title.isEmpty ? 'Request' : requisition.title,
      subtitle: requisition.statusLabel,
      iconColor: RequisitionCard.statusColor(requisition.status),
      actions: [
        if (canEdit)
          IconButton(
            onPressed: () => context.pushAppRoute(
              AppRoutes.createRequisition,
              extra: requisition,
            ),
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Summary(
            requisition: requisition,
            symbol: symbol,
            dateFormat: _dateFormat,
          ),
          const SizedBox(height: 12),
          _Lines(requisition: requisition, symbol: symbol),
          if (requisition.decisionNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DecisionNote(requisition: requisition),
          ],
          const SizedBox(height: 16),
          _Actions(
            requisition: requisition,
            canApprove: canApprove,
            canEdit: canEdit,
            busy: provider.isBusy,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.requisition,
    required this.symbol,
    required this.dateFormat,
  });

  final RequisitionModel requisition;
  final String symbol;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _Fact(label: 'Urgency', value: requisition.urgencyLabel),
              _Fact(label: 'Units', value: '${requisition.totalQuantity}'),
              _Fact(
                label: 'Estimate',
                value: Money.withSymbol(symbol, requisition.estimatedTotal),
              ),
              if (requisition.vendorName.isNotEmpty)
                _Fact(label: 'Supplier', value: requisition.vendorName),
              if (requisition.department.isNotEmpty)
                _Fact(label: 'Department', value: requisition.department),
            ],
          ),
          const Divider(height: 24),
          _Line(
            icon: Icons.person_rounded,
            text: 'Raised by ${requisition.requestedByName}',
          ),
          if (requisition.submittedAt != null)
            _Line(
              icon: Icons.send_rounded,
              text: 'Submitted ${dateFormat.format(requisition.submittedAt!)}',
            ),
          if (requisition.neededBy != null)
            _Line(
              icon: Icons.event_rounded,
              text:
                  'Needed by ${DateFormat('dd MMM yyyy').format(requisition.neededBy!)}',
            ),
          if (requisition.decidedAt != null)
            _Line(
              icon: requisition.status == RequisitionStatus.rejected
                  ? Icons.cancel_rounded
                  : Icons.verified_rounded,
              text:
                  '${requisition.status == RequisitionStatus.rejected ? 'Rejected' : 'Approved'} '
                  'by ${requisition.decidedByName} · '
                  '${dateFormat.format(requisition.decidedAt!)}',
            ),
          if (requisition.purchaseOrderId.isNotEmpty)
            _Line(
              icon: Icons.receipt_long_rounded,
              text: 'Ordered — a purchase order was raised from this request',
            ),
          if (requisition.justification.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              requisition.justification,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.textSec(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.requisition, required this.symbol});

  final RequisitionModel requisition;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Requested',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final line in requisition.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        if (line.note.isNotEmpty)
                          Text(
                            line.note,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${line.quantity} ${line.unit}'
                    '${line.estimatedTotal > 0 ? ' · ${Money.withSymbol(symbol, line.estimatedTotal)}' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DecisionNote extends StatelessWidget {
  const _DecisionNote({required this.requisition});

  final RequisitionModel requisition;

  @override
  Widget build(BuildContext context) {
    final rejected = requisition.status == RequisitionStatus.rejected;
    final color = rejected ? AppTheme.dangerColor : AppTheme.successColor;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            rejected ? Icons.report_problem_rounded : Icons.check_circle_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rejected ? 'Why it was rejected' : 'Approver note',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  requisition.decisionNote,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.requisition,
    required this.canApprove,
    required this.canEdit,
    required this.busy,
  });

  final RequisitionModel requisition;
  final bool canApprove;
  final bool canEdit;
  final bool busy;

  /// Asks for the decision note. Rejections require one — being told no
  /// without being told why is what makes an approval queue resented.
  Future<String?> _askForNote(BuildContext context, {required bool approved}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final text = controller.text.trim();
          return AlertDialog(
            title: Text(approved ? 'Approve request' : 'Reject request'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(
                labelText: approved ? 'Note (optional)' : 'Reason',
                hintText: approved
                    ? 'Anything the requester should know'
                    : 'Why this cannot go ahead',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !approved && text.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, text),
                child: Text(approved ? 'Approve' : 'Reject'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approved}) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final note = await _askForNote(context, approved: approved);
    if (note == null || !context.mounted) return;

    final provider = context.read<RequisitionProvider>();
    final ok = await provider.decide(
      requisition: requisition,
      approved: approved,
      note: note,
      userId: user.uid,
      userName: user.name,
    );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(
        context,
        approved ? 'Approved.' : 'Rejected.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Decision failed.');
    }
  }

  Future<void> _convert(BuildContext context) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final expected = await showDatePicker(
      context: context,
      initialDate: requisition.neededBy ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      helpText: 'Expected delivery date',
    );
    if (expected == null || !context.mounted) return;

    final provider = context.read<RequisitionProvider>();
    final orderId = await provider.convertToPurchaseOrder(
      requisition: requisition,
      expectedDate: expected,
      userId: user.uid,
      userName: user.name,
    );
    if (!context.mounted) return;
    if (orderId == null) {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'Could not raise the order.',
      );
      return;
    }
    showSuccessSnackBar(context, 'Draft purchase order raised.');
    context.pushAppRoute(AppRoutes.purchaseOrders);
  }

  Future<void> _submit(BuildContext context) async {
    final provider = context.read<RequisitionProvider>();
    final ok = await provider.submit(requisition);
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Sent for approval.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Submit failed.');
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this request?',
      message: 'It stays on file, marked cancelled.',
      confirmLabel: 'Cancel request',
    );
    if (!confirmed || !context.mounted) return;
    final provider = context.read<RequisitionProvider>();
    final ok = await provider.cancel(requisition);
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Request cancelled.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Cancel failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (canEdit && requisition.canSubmit)
        FilledButton.icon(
          onPressed: busy ? null : () => _submit(context),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Submit for approval'),
        ),
      if (canApprove && requisition.canDecide) ...[
        FilledButton.icon(
          onPressed: busy ? null : () => _decide(context, approved: true),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Approve'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _decide(context, approved: false),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Reject'),
        ),
      ],
      if (canApprove && requisition.canConvert)
        FilledButton.icon(
          onPressed: busy ? null : () => _convert(context),
          icon: const Icon(Icons.receipt_long_rounded, size: 18),
          label: const Text('Raise purchase order'),
        ),
      if (requisition.canCancel)
        TextButton.icon(
          onPressed: busy ? null : () => _cancel(context),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel request'),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
