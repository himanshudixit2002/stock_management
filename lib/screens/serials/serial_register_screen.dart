import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/serial_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/serial_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';
import 'register_serials_sheet.dart';
import 'serial_detail_sheet.dart';

/// The serial register: search, filter and act on individual tracked units.
class SerialRegisterScreen extends StatefulWidget {
  const SerialRegisterScreen({super.key});

  @override
  State<SerialRegisterScreen> createState() => _SerialRegisterScreenState();
}

class _SerialRegisterScreenState extends State<SerialRegisterScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  final TextEditingController _search = TextEditingController();
  SerialStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<SerialProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SerialModel> _filtered(List<SerialModel> serials) {
    final query = SerialModel.normalizeSerial(_search.text);
    return serials.where((serial) {
      if (_statusFilter != null && serial.status != _statusFilter) return false;
      if (query.isEmpty) return true;
      return serial.serialKey.contains(query) ||
          serial.productName.toUpperCase().contains(query);
    }).toList();
  }

  /// Looks a serial up on the server when the register's loaded page does not
  /// contain it — the page is capped, so a catalog of thousands would otherwise
  /// make search look broken for older units.
  Future<void> _searchRemote() async {
    final raw = _search.text.trim();
    if (raw.isEmpty) return;
    final provider = context.read<SerialProvider>();
    final found = await provider.lookup(raw);
    if (!mounted) return;
    if (found == null) {
      showInfoSnackBar(context, 'No unit carries "$raw".');
      return;
    }
    _open(found);
  }

  Future<void> _open(SerialModel serial) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    await showResponsiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => SerialDetailSheet(
        serial: serial,
        userId: user.uid,
        userName: user.name,
      ),
    );
  }

  Future<void> _register() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    await showResponsiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => RegisterSerialsSheet(
        products: context.read<ProductProvider>().analyticsProducts,
        userId: user.uid,
        userName: user.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewSerials,
      featureName: 'Serial Numbers',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<SerialProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageSerials) ?? false,
    );
    final serials = _filtered(provider.serials);
    final counts = provider.statusCounts;

    return AppScreenScaffold(
      icon: Icons.qr_code_2_rounded,
      title: 'Serial Numbers',
      subtitle: '${provider.serials.length} units loaded',
      iconColor: AppTheme.indigoColor,
      isLoading: provider.isLoading && provider.serials.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _register,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Register'),
            )
          : null,
      isEmpty: provider.serials.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.qr_code_2_rounded,
        title: 'No serialised units yet',
        subtitle:
            'Register units to track them individually — for warranty, returns '
            'and recalls, where a batch number is not specific enough.',
        buttonText: canManage ? 'Register units' : null,
        onButtonPressed: canManage ? _register : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _searchRemote(),
              decoration: InputDecoration(
                hintText: 'Search serial or product',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                ),
                for (final status in SerialStatus.values)
                  if ((counts[status] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          '${SerialModel.statusLabelOf(status)} '
                          '(${counts[status]})',
                        ),
                        selected: _statusFilter == status,
                        onSelected: (_) => setState(
                          () => _statusFilter =
                              _statusFilter == status ? null : status,
                        ),
                      ),
                    ),
              ],
            ),
          ),
          Expanded(
            child: serials.isEmpty
                ? _NoMatches(
                    query: _search.text.trim(),
                    onSearchRemote: _searchRemote,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: serials.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SerialRow(
                        serial: serials[i],
                        index: i,
                        dateFormat: _dateFormat,
                        onTap: () => _open(serials[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onSearchRemote});

  final String query;
  final VoidCallback onSearchRemote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppTheme.emptyIcon(context),
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'Nothing in this filter.'
                  : 'Nothing loaded matches "$query".',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSec(context)),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 12),
              // The register shows a capped page, so a miss here is not proof
              // the unit does not exist.
              OutlinedButton.icon(
                onPressed: onSearchRemote,
                icon: const Icon(Icons.cloud_download_rounded, size: 16),
                label: const Text('Search all units'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SerialRow extends StatelessWidget {
  const _SerialRow({
    required this.serial,
    required this.index,
    required this.dateFormat,
    required this.onTap,
  });

  final SerialModel serial;
  final int index;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  static Color statusColor(SerialStatus status) => switch (status) {
    SerialStatus.inStock => AppTheme.successColor,
    SerialStatus.allocated => AppTheme.infoColor,
    SerialStatus.sold => AppTheme.indigoColor,
    SerialStatus.returned => AppTheme.warningColor,
    SerialStatus.scrapped => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(serial.status);
    return AnimatedListItem(
      index: index,
      child: GlassCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.qr_code_2_rounded, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serial.serialNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        serial.productName,
                        if (serial.location.isNotEmpty) serial.location,
                        if (serial.batchNumber.isNotEmpty)
                          'Batch ${serial.batchNumber}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    serial.statusLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (serial.isUnderWarranty)
                    Text(
                      'Warranty to ${dateFormat.format(serial.warrantyUntil!)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
