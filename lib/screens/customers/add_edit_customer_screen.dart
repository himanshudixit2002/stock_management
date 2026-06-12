import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/validators.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/success_overlay.dart';

class AddEditCustomerScreen extends StatefulWidget {
  final CustomerModel? customer;

  const AddEditCustomerScreen({super.key, this.customer});

  @override
  State<AddEditCustomerScreen> createState() => _AddEditCustomerScreenState();
}

class _AddEditCustomerScreenState extends State<AddEditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _companyController;
  late final TextEditingController _notesController;
  bool _isLoading = false;
  bool _isActive = true;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _emailController = TextEditingController(
      text: widget.customer?.email ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.customer?.phone ?? '',
    );
    _addressController = TextEditingController(
      text: widget.customer?.address ?? '',
    );
    _companyController = TextEditingController(
      text: widget.customer?.company ?? '',
    );
    _notesController = TextEditingController(
      text: widget.customer?.notes ?? '',
    );
    _isActive = widget.customer?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _companyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final now = DateTime.now();
    final customer = CustomerModel(
      id: widget.customer?.id ?? '',
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      company: _companyController.text.trim(),
      notes: _notesController.text.trim(),
      totalOrders: widget.customer?.totalOrders ?? 0,
      totalSpent: widget.customer?.totalSpent ?? 0,
      isActive: _isActive,
      createdAt: widget.customer?.createdAt ?? now,
      updatedAt: now,
      createdBy: widget.customer?.createdBy ?? user.uid,
      createdByName: widget.customer?.createdByName ?? user.name,
    );

    String? newId;
    bool success;
    if (_isEditing) {
      success = await context.read<CustomerProvider>().updateCustomer(customer);
    } else {
      final result = await context.read<CustomerProvider>().addCustomer(
        customer,
      );
      success = result != null;
      newId = result?.id;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      HapticFeedback.mediumImpact();
      showSuccessOverlay(
        context,
        message: _isEditing ? 'Customer updated' : 'Customer added',
        popResult: newId,
      );
    } else {
      showErrorSnackBar(
        context,
        context.read<CustomerProvider>().errorMessage ?? 'Operation failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: _isEditing
          ? AppPermissions.editCustomers
          : AppPermissions.addCustomers,
      featureName: _isEditing ? 'Edit Customer' : 'Add Customer',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: _isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
          color: AppTheme.primaryColor,
          title: _isEditing ? 'Edit Customer' : 'Add Customer',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              child: GlassPanel(
                borderRadius: 20,
                padding: const EdgeInsets.all(20),
                useContentVariant: true,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ResponsiveFormRow(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Name *',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Name is required';
                              return null;
                            },
                          ),
                          TextFormField(
                            controller: _companyController,
                            decoration: const InputDecoration(
                              labelText: 'Company',
                              prefixIcon: Icon(Icons.business_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ResponsiveFormRow(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_rounded),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v != null &&
                                  v.isNotEmpty &&
                                  !v.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone *',
                              prefixIcon: Icon(Icons.phone_rounded),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: validateRequiredPhone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          prefixIcon: Icon(Icons.location_on_rounded),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          prefixIcon: Icon(Icons.note_rounded),
                        ),
                        maxLines: 2,
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text(
                            'Active',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          activeThumbColor: AppTheme.primaryColor,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _save,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _isEditing
                                    ? Icons.check_rounded
                                    : Icons.person_add_rounded,
                              ),
                        label: Text(
                          _isEditing ? 'Save Changes' : 'Add Customer',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
