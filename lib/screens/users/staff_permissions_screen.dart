import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';

class StaffPermissionsScreen extends StatelessWidget {
  const StaffPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.warningColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Staff Permissions'),
          ],
        ),
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: context.read<AuthProvider>().getAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = (snapshot.data ?? [])
              .where((u) => u.isStaff)
              .toList();

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('No staff users yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                ],
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
              child: ListView.separated(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            itemCount: users.length,
            separatorBuilder: (_, _a) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _StaffCard(user: users[i]),
          ),
            ),
          );
        },
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final UserModel user;
  const _StaffCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final initials = user.name.isNotEmpty
        ? user.name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    final enabledCount =
        user.permissions.values.where((v) => v).length;
    final totalCount = UserModel.allPermissionKeys.length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showPermissionSheet(context, user),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(initials,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: enabledCount == totalCount
                      ? AppTheme.successColor.withValues(alpha: 0.1)
                      : AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$enabledCount/$totalCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enabledCount == totalCount
                        ? AppTheme.successColor
                        : AppTheme.warningColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showPermissionSheet(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PermissionEditor(user: user),
    );
  }
}

class _PermissionEditor extends StatefulWidget {
  final UserModel user;
  const _PermissionEditor({required this.user});

  @override
  State<_PermissionEditor> createState() => _PermissionEditorState();
}

class _PermissionEditorState extends State<_PermissionEditor> {
  late Map<String, bool> _perms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _perms = {...UserModel.defaultPermissions, ...widget.user.permissions};
  }

  bool get _allEnabled => _perms.values.every((v) => v);

  void _toggleAll(bool value) {
    setState(() {
      for (final k in _perms.keys.toList()) {
        _perms[k] = value;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await context
        .read<AuthProvider>()
        .updateStaffPermissions(widget.user.uid, _perms);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Permissions updated' : 'Failed to update'),
          backgroundColor: ok ? AppTheme.successColor : AppTheme.dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.user.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Text('Manage permissions',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toggleAll(!_allEnabled),
                    child: Text(_allEnabled ? 'Deselect All' : 'Select All'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: UserModel.allPermissionKeys.map((key) {
                  return SwitchListTile(
                    value: _perms[key] ?? true,
                    onChanged: (v) => setState(() => _perms[key] = v),
                    title: Text(
                      UserModel.permissionLabels[key] ?? key,
                      style: const TextStyle(fontSize: 15),
                    ),
                    activeTrackColor: AppTheme.primaryColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Permissions'),
              ),
            ),
          ],
        );
      },
    );
  }
}
