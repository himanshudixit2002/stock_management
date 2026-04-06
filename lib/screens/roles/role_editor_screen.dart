import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/role_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/role_provider.dart';
import '../../utils/responsive.dart';

class RoleEditorScreen extends StatefulWidget {
  final RoleModel? role;
  const RoleEditorScreen({super.key, this.role});

  @override
  State<RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends State<RoleEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late Map<String, bool> _permissions;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.role != null;
  bool get _isOwnerRole => widget.role?.id == RoleModel.ownerRoleId;
  bool get _isReadOnly => _isOwnerRole;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.role?.description ?? '');
    _permissions = Map<String, bool>.from(
      widget.role?.permissions ?? AppPermissions.allFalse(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Role' : 'New Role'),
        actions: [
          if (!_isReadOnly)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save'),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 100),
              children: [
                _buildNameSection(),
                const SizedBox(height: 16),
                _buildCopyFromRole(),
                const SizedBox(height: 16),
                _buildPermissionSections(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Role Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPri(context),
              )),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            readOnly: _isReadOnly,
            decoration: const InputDecoration(
              labelText: 'Role Name',
              hintText: 'e.g. Warehouse Manager',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Role name is required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            readOnly: _isReadOnly,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What this role is for',
              prefixIcon: Icon(Icons.description_rounded),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildCopyFromRole() {
    if (_isReadOnly) return const SizedBox.shrink();
    final roles = context.watch<RoleProvider>().roles;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.cardDeco(context),
      child: Row(
        children: [
          Icon(Icons.copy_rounded,
              size: 20, color: AppTheme.textTer(context)),
          const SizedBox(width: 12),
          Text('Copy from:',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textTer(context),
              )),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: null,
              hint: const Text('Select a role to copy permissions'),
              items: roles.map((r) {
                return DropdownMenuItem(value: r.id, child: Text(r.name));
              }).toList(),
              onChanged: (roleId) {
                if (roleId == null) return;
                final source = roles.firstWhere((r) => r.id == roleId);
                setState(() {
                  _permissions = Map<String, bool>.from(source.permissions);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Permissions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                )),
            if (!_isReadOnly)
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _permissions = AppPermissions.allTrue();
                    }),
                    child: const Text('Select All'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _permissions = AppPermissions.allFalse();
                    }),
                    child: const Text('Deselect All'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...AppPermissions.groups.map((group) {
          final perms = AppPermissions.byGroup(group.id);
          if (perms.isEmpty) return const SizedBox.shrink();
          return _PermissionGroupSection(
            group: group,
            permissions: perms,
            values: _permissions,
            readOnly: _isReadOnly,
            onChanged: (key, value) {
              setState(() => _permissions[key] = value);
            },
            onToggleAll: (value) {
              setState(() {
                for (final p in perms) {
                  _permissions[p.key] = value;
                }
              });
            },
          );
        }),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final provider = context.read<RoleProvider>();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (_isEditing) {
      final updated = widget.role!.copyWith(
        name: name,
        description: description,
        permissions: _permissions,
        updatedAt: DateTime.now(),
      );
      await provider.updateRole(updated);
    } else {
      final now = DateTime.now();
      final companyId = provider.roles.isNotEmpty
          ? provider.roles.first.companyId
          : context.read<AuthProvider>().currentUser?.companyId ?? '';
      final role = RoleModel(
        id: '',
        name: name,
        description: description,
        permissions: _permissions,
        isSystem: false,
        companyId: companyId,
        createdAt: now,
        updatedAt: now,
      );
      await provider.addRole(role);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Role updated' : 'Role created'),
        ),
      );
    }
  }
}

class _PermissionGroupSection extends StatefulWidget {
  final PermissionGroup group;
  final List<PermissionDef> permissions;
  final Map<String, bool> values;
  final bool readOnly;
  final void Function(String key, bool value) onChanged;
  final void Function(bool value) onToggleAll;

  const _PermissionGroupSection({
    required this.group,
    required this.permissions,
    required this.values,
    required this.readOnly,
    required this.onChanged,
    required this.onToggleAll,
  });

  @override
  State<_PermissionGroupSection> createState() =>
      _PermissionGroupSectionState();
}

class _PermissionGroupSectionState extends State<_PermissionGroupSection> {
  bool _expanded = false;

  int get _enabledCount =>
      widget.permissions.where((p) => widget.values[p.key] == true).length;
  bool get _allEnabled => _enabledCount == widget.permissions.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDeco(context),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.group.icon,
                      size: 22, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.group.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPri(context),
                            )),
                        Text(
                          '$_enabledCount/${widget.permissions.length} enabled',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.readOnly)
                    TextButton(
                      onPressed: () => widget.onToggleAll(!_allEnabled),
                      child: Text(_allEnabled ? 'None' : 'All',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textTer(context),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: widget.permissions.map((perm) {
                  final value = widget.values[perm.key] ?? false;
                  return SwitchListTile(
                    value: value,
                    onChanged: widget.readOnly
                        ? null
                        : (v) => widget.onChanged(perm.key, v),
                    title: Text(perm.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPri(context),
                        )),
                    subtitle: Text(perm.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTer(context),
                        )),
                    secondary: Icon(perm.icon,
                        size: 20,
                        color: value
                            ? AppTheme.primaryColor
                            : AppTheme.iconMute(context)),
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
