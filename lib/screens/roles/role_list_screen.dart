import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/role_model.dart';
import '../../providers/role_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/shimmer_loading.dart';

class RoleListScreen extends StatelessWidget {
  const RoleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageRoles,
      featureName: 'Role Management',
      child: const _RoleListBody(),
    );
  }
}

class _RoleListBody extends StatelessWidget {
  const _RoleListBody();

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<RoleProvider>();
    final roles = roleProvider.roles;
    final systemRoles = roles.where((r) => r.isSystem).toList();
    final customRoles = roles.where((r) => !r.isSystem).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About Roles',
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.roleEditor),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Role'),
      ),
      body: roleProvider.isLoading && roles.isEmpty
          ? Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.contentMaxWidth(context),
                ),
                child: const ShimmerLoading(layout: ShimmerLayout.listTile),
              ),
            )
          : roles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.admin_panel_settings_rounded,
                      size: 64, color: AppTheme.emptyIcon(context)),
                  const SizedBox(height: 16),
                  Text('No roles found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
                      )),
                  const SizedBox(height: 8),
                  Text('Roles will appear here once created.',
                      style: TextStyle(
                        color: AppTheme.textTer(context),
                      )),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 100),
                  children: [
                    if (systemRoles.isNotEmpty) ...[
                      _sectionHeader(context, 'System Roles'),
                      const SizedBox(height: 8),
                      ...systemRoles.map((r) => _RoleCard(role: r)),
                      const SizedBox(height: 16),
                    ],
                    if (customRoles.isNotEmpty) ...[
                      _sectionHeader(context, 'Custom Roles'),
                      const SizedBox(height: 8),
                      ...customRoles.map((r) => _RoleCard(role: r)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textTer(context),
        letterSpacing: 0.5,
      ),
    );
  }

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About Roles',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPri(context),
                )),
            const SizedBox(height: 16),
            Text(
              'Roles define what users can see and do in the app. '
              'System roles (Owner, Admin, Manager, Staff, Viewer) are built-in and '
              'cover common use cases. You can create custom roles with specific '
              'permission combinations for your team.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textTer(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Users can also have per-user permission overrides on top of their role.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textTer(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final RoleModel role;
  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDeco(context),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: _gradientForRole(role),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconForRole(role), color: Colors.white, size: 22),
        ),
        title: Row(
          children: [
            Text(role.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                )),
            if (role.isSystem) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('SYSTEM',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                      letterSpacing: 0.5,
                    )),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (role.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(role.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTer(context),
                  )),
            ],
            const SizedBox(height: 4),
            Text(
              '${role.enabledCount}/${role.totalCount} permissions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        trailing: _buildPopupMenu(context),
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.roleEditor,
          arguments: role,
        ),
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context) {
    final isOwnerRole = role.id == RoleModel.ownerRoleId;
    return PopupMenuButton<String>(
      onSelected: (value) => _onMenuAction(context, value),
      itemBuilder: (_) => [
        if (!isOwnerRole)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        if (!role.isSystem)
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: AppTheme.dangerColor)),
          ),
      ],
    );
  }

  void _onMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        Navigator.pushNamed(context, AppRoutes.roleEditor, arguments: role);
        break;
      case 'duplicate':
        _duplicateRole(context);
        break;
      case 'delete':
        _confirmDelete(context);
        break;
    }
  }

  void _duplicateRole(BuildContext context) async {
    final nameController = TextEditingController(text: '${role.name} (Copy)');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate Role'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'New Role Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      await context.read<RoleProvider>().duplicateRole(role, result);
      if (context.mounted) {
        showSuccessSnackBar(context, 'Role "$result" created');
      }
    }
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text(
          'Are you sure you want to delete "${role.name}"? '
          'Users with this role will need to be reassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final success = await context.read<RoleProvider>().deleteRole(role.id);
      if (context.mounted && success) {
        showSuccessSnackBar(context, 'Role "${role.name}" deleted');
      }
    }
  }

  LinearGradient _gradientForRole(RoleModel role) {
    switch (role.id) {
      case RoleModel.ownerRoleId:
        return AppTheme.heroGradient;
      case RoleModel.adminRoleId:
        return AppTheme.primaryGradient;
      case RoleModel.managerRoleId:
        return AppTheme.indigoGradient;
      case RoleModel.staffRoleId:
        return AppTheme.successGradient;
      case RoleModel.viewerRoleId:
        return AppTheme.warmGradient;
      default:
        return AppTheme.warningGradient;
    }
  }

  IconData _iconForRole(RoleModel role) {
    switch (role.id) {
      case RoleModel.ownerRoleId:
        return Icons.shield_rounded;
      case RoleModel.adminRoleId:
        return Icons.admin_panel_settings_rounded;
      case RoleModel.managerRoleId:
        return Icons.manage_accounts_rounded;
      case RoleModel.staffRoleId:
        return Icons.person_rounded;
      case RoleModel.viewerRoleId:
        return Icons.visibility_rounded;
      default:
        return Icons.badge_rounded;
    }
  }
}
