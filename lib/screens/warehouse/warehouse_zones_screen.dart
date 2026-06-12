import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/warehouse_zone_model.dart';
import '../../providers/warehouse_zone_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../utils/dialogs.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animations.dart';
import '../../widgets/success_overlay.dart';

class WarehouseZonesScreen extends StatelessWidget {
  const WarehouseZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageWarehouseZones,
      featureName: 'Warehouse Zones',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final zones = context.watch<WarehouseZoneProvider>().zones;
    final isLoading = context.watch<WarehouseZoneProvider>().isLoading;
    final locations = context.watch<SettingsProvider>().locations;

    final grouped = <String, List<WarehouseZoneModel>>{};
    for (final z in zones) {
      final loc = z.locationName.isNotEmpty ? z.locationName : 'Unassigned';
      grouped.putIfAbsent(loc, () => []).add(z);
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.warehouse_rounded,
          color: AppTheme.indigoColor,
          title: 'Warehouse Zones',
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showZoneForm(context, locations: locations),
        child: const Icon(Icons.add_rounded),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: isLoading
            ? const ShimmerLoading(layout: ShimmerLayout.card)
            : zones.isEmpty
            ? EmptyStateWidget(
                icon: Icons.warehouse_rounded,
                title: 'No Zones Yet',
                subtitle:
                    'Organize your warehouse into zones and bins for better tracking.',
                buttonText: 'Add Zone',
                onButtonPressed: () =>
                    _showZoneForm(context, locations: locations),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: ListView(
                    padding: EdgeInsets.all(
                      Responsive.horizontalPadding(context),
                    ),
                    children: grouped.entries.toList().asMap().entries.map((e) {
                      final entry = e.value;
                      return FadeSlideIn(
                        index: e.key,
                        child: _buildLocationSection(
                          context,
                          entry.key,
                          entry.value,
                          locations,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLocationSection(
    BuildContext context,
    String locationName,
    List<WarehouseZoneModel> zones,
    List<String> locations,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                locationName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${zones.length} zone${zones.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...zones.map((z) => _ZoneCard(zone: z, locations: locations)),
        const SizedBox(height: 8),
      ],
    );
  }

  void _showZoneForm(
    BuildContext context, {
    WarehouseZoneModel? zone,
    required List<String> locations,
  }) {
    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ZoneFormSheet(zone: zone, locations: locations),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final WarehouseZoneModel zone;
  final List<String> locations;

  const _ZoneCard({required this.zone, required this.locations});

  @override
  Widget build(BuildContext context) {
    final capacityRatio = zone.capacity > 0
        ? (zone.currentStock / zone.capacity).clamp(0.0, 1.0)
        : 0.0;
    final capacityColor = capacityRatio > 0.9
        ? AppTheme.dangerColor
        : capacityRatio > 0.7
        ? AppTheme.warningColor
        : AppTheme.successColor;
    final statusColor = zone.isActive
        ? AppTheme.successColor
        : AppTheme.textSec(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.indigoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    color: AppTheme.indigoColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zone.zoneName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (zone.binCode.isNotEmpty)
                        Text(
                          'Bin: ${zone.binCode}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    zone.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_rounded,
                            size: 18,
                            color: AppTheme.dangerColor,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.dangerColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (zone.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                zone.description,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSec(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (zone.capacity > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Capacity: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                  Text(
                    '${zone.currentStock} / ${zone.capacity}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: capacityColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: capacityRatio,
                  minHeight: 6,
                  backgroundColor: AppTheme.dividerC(context),
                  valueColor: AlwaysStoppedAnimation<Color>(capacityColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        showModalBottomSheet(
          context: context,
          constraints: Responsive.sheetConstraints(context),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _ZoneFormSheet(zone: zone, locations: locations),
        );
        break;
      case 'delete':
        _confirmDelete(context);
        break;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Zone',
      message: 'Are you sure you want to delete "${zone.zoneName}"?',
    );
    if (!confirm || !context.mounted) return;
    context.read<WarehouseZoneProvider>().deleteZone(zone.id);
  }
}

class _ZoneFormSheet extends StatefulWidget {
  final WarehouseZoneModel? zone;
  final List<String> locations;

  const _ZoneFormSheet({this.zone, required this.locations});

  @override
  State<_ZoneFormSheet> createState() => _ZoneFormSheetState();
}

class _ZoneFormSheetState extends State<_ZoneFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late String? _selectedLocation;
  late final TextEditingController _zoneNameController;
  late final TextEditingController _binCodeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _capacityController;
  bool _isSubmitting = false;

  bool get _isEditing => widget.zone != null;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.zone?.locationName;
    _zoneNameController = TextEditingController(
      text: widget.zone?.zoneName ?? '',
    );
    _binCodeController = TextEditingController(
      text: widget.zone?.binCode ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.zone?.description ?? '',
    );
    _capacityController = TextEditingController(
      text: widget.zone != null && widget.zone!.capacity > 0
          ? widget.zone!.capacity.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _zoneNameController.dispose();
    _binCodeController.dispose();
    _descriptionController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      showErrorSnackBar(context, 'Please select a location');
      return;
    }
    setState(() => _isSubmitting = true);

    final now = DateTime.now();
    final zone = WarehouseZoneModel(
      id: widget.zone?.id ?? '',
      locationName: _selectedLocation!,
      zoneName: _zoneNameController.text.trim(),
      binCode: _binCodeController.text.trim(),
      description: _descriptionController.text.trim(),
      capacity: int.tryParse(_capacityController.text) ?? 0,
      currentStock: widget.zone?.currentStock ?? 0,
      isActive: widget.zone?.isActive ?? true,
      createdAt: widget.zone?.createdAt ?? now,
      updatedAt: now,
    );

    final provider = context.read<WarehouseZoneProvider>();
    bool success;
    if (_isEditing) {
      success = await provider.updateZone(zone);
    } else {
      success = (await provider.addZone(zone)) != null;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      showSuccessOverlay(
        context,
        message: _isEditing ? 'Zone updated' : 'Zone added',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Operation failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.emptyIcon(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Zone' : 'Add Zone',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
              ),
              const SizedBox(height: 20),
              FormField<String>(
                validator: (_) =>
                    _selectedLocation == null || _selectedLocation!.isEmpty
                    ? 'Select a location'
                    : null,
                builder: (field) => GestureDetector(
                  onTap: () async {
                    final result = await showSearchablePicker(
                      context: context,
                      title: 'Location',
                      selectedValue: _selectedLocation,
                      items: widget.locations
                          .map(
                            (l) => PickerItem(
                              value: l,
                              label: l,
                              icon: Icons.location_on_rounded,
                              iconColor: AppTheme.primaryColor,
                            ),
                          )
                          .toList(),
                    );
                    if (result != null) {
                      setState(() => _selectedLocation = result);
                      field.didChange(result);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Location *',
                      prefixIcon: const Icon(Icons.location_on_rounded),
                      errorText: field.errorText,
                    ),
                    child: Text(
                      _selectedLocation ?? 'Tap to select',
                      style: TextStyle(
                        color: _selectedLocation != null
                            ? null
                            : AppTheme.textSec(context),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _zoneNameController,
                decoration: const InputDecoration(
                  labelText: 'Zone Name *',
                  prefixIcon: Icon(Icons.grid_view_rounded),
                  hintText: 'e.g., Zone A',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter zone name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _binCodeController,
                decoration: const InputDecoration(
                  labelText: 'Bin Code',
                  prefixIcon: Icon(Icons.qr_code_rounded),
                  hintText: 'e.g., A-01-01',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(
                  labelText: 'Capacity (units)',
                  prefixIcon: Icon(Icons.all_inbox_rounded),
                  hintText: '0 = unlimited',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 24),
              _isSubmitting
                  ? SizedBox(
                      height: 52,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    )
                  : ShimmerButton(
                      label: _isEditing ? 'Update Zone' : 'Add Zone',
                      icon: Icons.check_rounded,
                      onPressed: _save,
                    ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
