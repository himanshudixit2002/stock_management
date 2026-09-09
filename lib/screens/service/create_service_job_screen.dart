import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/serial_model.dart';
import '../../models/service_job_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/serial_provider.dart';
import '../../providers/service_job_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';

/// Books a unit in for repair.
class CreateServiceJobScreen extends StatefulWidget {
  const CreateServiceJobScreen({super.key, this.serial});

  /// Pre-fills the unit when the job is raised from a serial's detail sheet.
  final SerialModel? serial;

  @override
  State<CreateServiceJobScreen> createState() => _CreateServiceJobScreenState();
}

class _CreateServiceJobScreenState extends State<CreateServiceJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _jobNumber = TextEditingController();
  final _fault = TextEditingController();
  final _technician = TextEditingController();
  final _notes = TextEditingController();

  String _customerId = '';
  String _customerName = '';
  String _customerPhone = '';
  String _productId = '';
  String _productName = '';
  String _serialId = '';
  String _serialNumber = '';
  DateTime? _warrantyUntil;
  DateTime? _promisedAt;

  @override
  void initState() {
    super.initState();
    final serial = widget.serial;
    if (serial != null) {
      _serialId = serial.id;
      _serialNumber = serial.serialNumber;
      _productId = serial.productId;
      _productName = serial.productName;
      _warrantyUntil = serial.warrantyUntil;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isEmpty) return;
      context.read<ServiceJobProvider>().initialize(companyId: companyId);
      context.read<SerialProvider>().initialize(companyId: companyId);
    });
  }

  @override
  void dispose() {
    _jobNumber.dispose();
    _fault.dispose();
    _technician.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final customers = context.read<CustomerProvider>().customers;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Whose unit is it?',
      selectedValue: _customerId.isEmpty ? null : _customerId,
      items: [
        for (final c in customers)
          PickerItem(
            value: c.id,
            label: c.name,
            subtitle: c.phone,
            icon: Icons.person_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final customer = context.read<CustomerProvider>().customers.firstWhere(
      (c) => c.id == selected,
    );
    setState(() {
      _customerId = customer.id;
      _customerName = customer.name;
      _customerPhone = customer.phone;
    });
  }

  Future<void> _pickSerial() async {
    final serials = context.read<SerialProvider>().serials;
    if (serials.isEmpty) {
      showInfoSnackBar(
        context,
        'No serial numbers are registered. Pick the product instead.',
      );
      return;
    }
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which unit?',
      selectedValue: _serialId.isEmpty ? null : _serialId,
      items: [
        for (final serial in serials)
          PickerItem(
            value: serial.id,
            label: serial.serialNumber,
            subtitle: serial.productName,
            icon: Icons.qr_code_2_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final serial = serials.firstWhere((s) => s.id == selected);
    setState(() {
      _serialId = serial.id;
      _serialNumber = serial.serialNumber;
      _productId = serial.productId;
      _productName = serial.productName;
      // Copied, not read live: the warranty position of a job is a fact about
      // the day the unit came in.
      _warrantyUntil = serial.warrantyUntil;
    });
  }

  Future<void> _pickProduct() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Which product?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _productId = picked.id;
      _productName = picked.name;
    });
  }

  Future<void> _pickPromised() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _promisedAt ?? now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) setState(() => _promisedAt = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_productId.isEmpty && _serialId.isEmpty) {
      showErrorSnackBar(context, 'Choose the unit or the product being repaired.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ServiceJobProvider>();
    final now = DateTime.now();

    final job = ServiceJobModel(
      id: '',
      jobNumber: _jobNumber.text.trim(),
      customerId: _customerId,
      customerName: _customerName,
      customerPhone: _customerPhone,
      productId: _productId,
      productName: _productName,
      serialId: _serialId,
      serialNumber: _serialNumber,
      warrantyUntil: _warrantyUntil,
      status: ServiceJobStatus.received,
      faultDescription: _fault.text.trim(),
      technicianId: '',
      technicianName: _technician.text.trim(),
      promisedAt: _promisedAt,
      receivedAt: now,
      notes: _notes.text.trim(),
      createdBy: user?.uid ?? '',
      createdByName: user?.name ?? '',
      createdAt: now,
      updatedAt: now,
    );

    final id = await provider.addJob(job);
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Job booked in.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageServiceJobs,
      featureName: 'Service Jobs',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<ServiceJobProvider>().isBusy;
    final inWarranty =
        _warrantyUntil != null && DateTime.now().isBefore(_warrantyUntil!);

    return AppScreenScaffold(
      icon: Icons.build_circle_rounded,
      title: 'Book a Job In',
      iconColor: AppTheme.infoColor,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'The unit',
              icon: Icons.qr_code_2_rounded,
              index: 0,
              children: [
                EntityPickerField(
                  label: 'Serial number',
                  icon: Icons.qr_code_2_rounded,
                  value: _serialNumber.isEmpty ? null : _serialNumber,
                  detail: _warrantyUntil == null
                      ? 'No warranty date on this unit'
                      : (inWarranty
                            ? 'In warranty until '
                                  '${_warrantyUntil!.day}/${_warrantyUntil!.month}/${_warrantyUntil!.year}'
                            : 'Warranty expired '
                                  '${_warrantyUntil!.day}/${_warrantyUntil!.month}/${_warrantyUntil!.year}'),
                  onTap: _pickSerial,
                  onClear: _serialId.isEmpty
                      ? null
                      : () => setState(() {
                          _serialId = '';
                          _serialNumber = '';
                          _warrantyUntil = null;
                        }),
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Product',
                  icon: Icons.inventory_2_rounded,
                  value: _productName.isEmpty ? null : _productName,
                  onTap: _pickProduct,
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Customer',
                  icon: Icons.person_rounded,
                  value: _customerName.isEmpty ? null : _customerName,
                  detail: _customerPhone.isEmpty ? null : _customerPhone,
                  onTap: _pickCustomer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'What is wrong',
              icon: Icons.report_problem_rounded,
              index: 1,
              children: [
                CustomTextField(
                  controller: _fault,
                  label: 'Reported fault',
                  maxLines: 3,
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Describe the fault as the customer reported it'
                      : null,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _jobNumber,
                  label: 'Job number (optional)',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _technician,
                  label: 'Technician (optional)',
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickPromised,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _promisedAt == null
                                ? 'Promised back (optional)'
                                : 'Promised '
                                      '${_promisedAt!.day}/${_promisedAt!.month}/${_promisedAt!.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_promisedAt != null)
                          IconButton(
                            onPressed: () =>
                                setState(() => _promisedAt = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Book the job in'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Parts are added on the job itself, and only leave stock when '
              'they are issued.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
