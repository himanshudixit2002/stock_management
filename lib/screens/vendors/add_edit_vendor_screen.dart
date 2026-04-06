import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/vendor_model.dart';
import '../../widgets/glass_panel.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/success_overlay.dart';

class AddEditVendorScreen extends StatefulWidget {
  final VendorModel? vendor;
  const AddEditVendorScreen({super.key, this.vendor});

  @override
  State<AddEditVendorScreen> createState() => _AddEditVendorScreenState();
}

class _AddEditVendorScreenState extends State<AddEditVendorScreen> {
  var _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _leadTimeCtrl;
  late final TextEditingController _notesCtrl;
  late double _rating;
  late bool _isActive;
  bool _saving = false;
  bool _saved = false;

  bool get _isEditing => widget.vendor != null;

  bool get _hasUnsavedChanges {
    if (_saved) return false;
    if (_isEditing) {
      final v = widget.vendor!;
      final origLeadTime = v.leadTimeDays > 0 ? v.leadTimeDays.toString() : '';
      return _nameCtrl.text.trim() != v.name ||
          _contactNameCtrl.text.trim() != v.contactName ||
          _emailCtrl.text.trim() != v.email ||
          _phoneCtrl.text.trim() != v.phone ||
          _addressCtrl.text.trim() != v.address ||
          _leadTimeCtrl.text.trim() != origLeadTime ||
          _notesCtrl.text.trim() != v.notes ||
          _rating != v.rating ||
          _isActive != v.isActive;
    }
    return _nameCtrl.text.trim().isNotEmpty ||
        _contactNameCtrl.text.trim().isNotEmpty ||
        _emailCtrl.text.trim().isNotEmpty ||
        _phoneCtrl.text.trim().isNotEmpty ||
        _addressCtrl.text.trim().isNotEmpty ||
        _leadTimeCtrl.text.trim().isNotEmpty ||
        _notesCtrl.text.trim().isNotEmpty ||
        _rating != 0;
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to go back?',
      confirmLabel: 'Discard',
    );
  }

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    _nameCtrl = TextEditingController(text: v?.name ?? '');
    _contactNameCtrl = TextEditingController(text: v?.contactName ?? '');
    _emailCtrl = TextEditingController(text: v?.email ?? '');
    _phoneCtrl = TextEditingController(text: v?.phone ?? '');
    _addressCtrl = TextEditingController(text: v?.address ?? '');
    _leadTimeCtrl = TextEditingController(
      text: v != null && v.leadTimeDays > 0 ? v.leadTimeDays.toString() : '',
    );
    _notesCtrl = TextEditingController(text: v?.notes ?? '');
    _rating = v?.rating ?? 0;
    _isActive = v?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _leadTimeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      setState(() => _saving = false);
      return;
    }

    final now = DateTime.now();
    final vendor = VendorModel(
      id: widget.vendor?.id ?? '',
      name: _nameCtrl.text.trim(),
      contactName: _contactNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      leadTimeDays: int.tryParse(_leadTimeCtrl.text.trim()) ?? 0,
      rating: _rating,
      notes: _notesCtrl.text.trim(),
      isActive: _isActive,
      createdAt: widget.vendor?.createdAt ?? now,
      updatedAt: now,
      createdBy: widget.vendor?.createdBy ?? user.uid,
      createdByName: widget.vendor?.createdByName ?? user.name,
    );

    final vendorProvider = context.read<VendorProvider>();
    String? newId;
    bool success = false;
    if (_isEditing) {
      success = await vendorProvider.updateVendorAndPropagate(
        vendor,
        oldName: widget.vendor?.name,
      );
    } else {
      final result = await vendorProvider.addVendor(vendor);
      success = result != null;
      newId = result?.id;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      _saved = true;
      HapticFeedback.mediumImpact();
      if (mounted) {
        showSuccessOverlay(
          context,
          message: _isEditing ? 'Vendor updated!' : 'Vendor added!',
          popResult: newId,
        );
      }
    } else if (mounted) {
      showErrorSnackBar(context,
          vendorProvider.errorMessage ?? 'Failed to save vendor');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final hasAdd = user?.hasPermission(AppPermissions.addVendors) ?? false;
    final hasEdit = user?.hasPermission(AppPermissions.editVendors) ?? false;
    if (_isEditing && !hasEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Vendor')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }
    if (!_isEditing && !hasAdd) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Vendor')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          if (_submitted) {
            setState(() {
              _submitted = false;
              _formKey = GlobalKey<FormState>();
            });
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.bg(context),
          appBar: AppBar(
            title: Text(_isEditing ? 'Edit Vendor' : 'Add Vendor'),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: AppTheme.scaffoldGrad(context),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.formMaxWidth(context),
                ),
                child: GlassPanel(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(20),
                  useContentVariant: true,
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.all(
                        Responsive.horizontalPadding(context),
                      ),
                      children: [
                        ResponsiveFormRow(
                          children: [
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Vendor Name *',
                                prefixIcon: Icon(Icons.business_rounded),
                              ),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Name is required'
                                  : null,
                            ),
                            TextFormField(
                              controller: _contactNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Contact Person',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ResponsiveFormRow(
                          children: [
                            TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_rounded),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final email = v.trim();
                                  if (!RegExp(
                                    r'^[\w\-.+]+@[\w\-]+\.[\w\-.]+$',
                                  ).hasMatch(email)) {
                                    return 'Enter a valid email address';
                                  }
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                prefixIcon: Icon(Icons.phone_rounded),
                              ),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  if (v.trim().length < 7) {
                                    return 'Phone number is too short';
                                  }
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _addressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            prefixIcon: Icon(Icons.location_on_rounded),
                          ),
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _leadTimeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Lead Time (days)',
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Text(
                              'Rating:',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ...List.generate(5, (i) {
                              return GestureDetector(
                                onTap: () => setState(
                                  () => _rating = (_rating == i + 1)
                                      ? 0
                                      : (i + 1).toDouble(),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Icon(
                                    i < _rating.round()
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 32,
                                    color: i < _rating.round()
                                        ? AppTheme.warningColor
                                        : AppTheme.emptyIcon(context),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _isActive
                                ? 'Vendor is available for selection'
                                : 'Vendor is hidden from selection',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textTer(context),
                            ),
                          ),
                          value: _isActive,
                          activeTrackColor: AppTheme.successColor,
                          onChanged: (v) => setState(() => _isActive = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 28),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppTheme.coloredShadow(
                              AppTheme.primaryColor,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isEditing ? 'Update Vendor' : 'Add Vendor',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
      ),
    );
  }
}
