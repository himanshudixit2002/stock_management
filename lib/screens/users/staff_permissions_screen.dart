import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../models/role_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/role_provider.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/shimmer_loading.dart';

class StaffPermissionsScreen extends StatelessWidget {
  const StaffPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageUsers,
      featureName: 'Permission Overrides',
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.shield_rounded,
            color: AppTheme.warningColor,
            title: 'User Permission Overrides',
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: StreamBuilder<List<UserModel>>(
            stream: context.read<AuthProvider>().getAllUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const ShimmerLoading(layout: ShimmerLayout.listTile);
              }
              final currentUid = context.read<AuthProvider>().currentUser?.uid;
              final users = (snapshot.data ?? [])
                  .where((u) => u.uid != currentUid)
                  .toList();

              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: AppTheme.emptyIcon(context),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No other users yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textTer(context),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.formMaxWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          16,
                          Responsive.horizontalPadding(context),
                          8,
                        ),
                        child: Text(
                          'Override permissions for individual users on top of their role.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.all(
                            Responsive.horizontalPadding(context),
                          ),
                          itemCount: users.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) =>
                              _UserOverrideCard(user: users[i]),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UserOverrideCard extends StatelessWidget {
  final UserModel user;
  const _UserOverrideCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<RoleProvider>();
    final role = roleProvider.getRoleById(user.roleId);
    final roleName = role?.name ?? 'Unknown';

    final overrideCount = user.permissions.entries.where((e) {
      final roleVal = role?.permissions[e.key] ?? false;
      return e.value != roleVal;
    }).length;

    final initials = user.name.trim().isNotEmpty
        ? user.name
              .trim()
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0])
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    return GlassCard(
      borderRadius: 14,
      onTap: () => _showOverrideSheet(context, user, role),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              child: Text(
                initials,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        roleName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (overrideCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$overrideCount override${overrideCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.warningColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textSec(context)),
          ],
        ),
      ),
    );
  }

  void _showOverrideSheet(
    BuildContext context,
    UserModel user,
    RoleModel? role,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: Responsive.sheetConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OverrideEditor(user: user, role: role),
    );
  }
}

class _OverrideEditor extends StatefulWidget {
  final UserModel user;
  final RoleModel? role;
  const _OverrideEditor({required this.user, this.role});

  @override
  State<_OverrideEditor> createState() => _OverrideEditorState();
}

class _OverrideEditorState extends State<_OverrideEditor> {
  late Map<String, bool> _overrides;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overrides = Map<String, bool>.from(widget.user.permissions);
  }

  void _clearOverrides() {
    setState(() {
      _overrides = {};
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await context.read<AuthProvider>().updateStaffPermissions(
      widget.user.uid,
      _overrides,
    );
    if (mounted) {
      Navigator.pop(context);
      if (ok) {
        showSuccessSnackBar(context, 'Permission overrides saved');
      } else {
        showErrorSnackBar(context, 'Failed to save');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolePerms = widget.role?.permissions ?? AppPermissions.allFalse();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.emptyIcon(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Role: ${widget.role?.name ?? "Unknown"} — Override individual permissions',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _clearOverrides,
                    child: const Text(
                      'Reset All',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: AppPermissions.groups.map((group) {
                  final perms = AppPermissions.byGroup(group.id);
                  return ExpansionTile(
                    leading: Icon(
                      group.icon,
                      size: 20,
                      color: AppTheme.primaryColor,
                    ),
                    title: Text(
                      group.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: perms.map((perm) {
                      final roleVal = rolePerms[perm.key] ?? false;
                      final overrideVal = _overrides[perm.key];
                      final effectiveVal = overrideVal ?? roleVal;
                      final isOverridden =
                          overrideVal != null && overrideVal != roleVal;

                      return SwitchListTile(
                        value: effectiveVal,
                        onChanged: (v) {
                          setState(() {
                            if (v == roleVal) {
                              _overrides.remove(perm.key);
                            } else {
                              _overrides[perm.key] = v;
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Text(
                              perm.label,
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (isOverridden) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warningColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'OVERRIDE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.warningColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          isOverridden
                              ? 'Role default: ${roleVal ? "ON" : "OFF"}'
                              : 'From role',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOverridden
                                ? AppTheme.warningColor
                                : AppTheme.textTer(context),
                          ),
                        ),
                        secondary: Icon(
                          perm.icon,
                          size: 18,
                          color: effectiveVal
                              ? AppTheme.primaryColor
                              : AppTheme.iconMute(context),
                        ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.surface(context),
                        ),
                      )
                    : const Text('Save Overrides'),
              ),
            ),
          ],
        );
      },
    );
  }
}
