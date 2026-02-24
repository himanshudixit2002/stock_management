import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final initials = user.name.isNotEmpty
        ? user.name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    return Center(
      child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
      child: ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context), 24,
        Responsive.horizontalPadding(context), 40,
      ),
      children: [
        // Profile card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            user.isSuperAdmin ? 'SUPER ADMIN' : user.isAdmin ? 'ADMIN' : 'STAFF',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (user.companyName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              user.companyName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _SectionHeader(title: 'Account', color: AppTheme.primaryColor),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.person_rounded,
              iconColor: AppTheme.primaryColor,
              title: 'Edit Profile',
              subtitle: 'Update your name and phone',
              onTap: () => _showEditProfileDialog(context),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.lock_reset_rounded,
              iconColor: AppTheme.indigoColor,
              title: 'Change Password',
              onTap: () => _showChangePasswordDialog(context),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.delete_forever_rounded,
              iconColor: AppTheme.dangerColor,
              title: 'Delete Account',
              subtitle: 'Permanently delete your account and data',
              onTap: () => _showDeleteAccountDialog(context),
            ),
          ],
        ),

        if (user.isAdmin) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: 'Features', color: AppTheme.infoColor),
          _SettingsCard(
            children: [
              Consumer<SettingsProvider>(
                builder: (context, settings, _) => SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.attach_money_rounded,
                        color: AppTheme.successColor, size: 20),
                  ),
                  title: const Text('Enable Pricing',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Show cost & selling price on products',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  value: settings.pricingEnabled,
                  activeTrackColor: AppTheme.successColor,
                  onChanged: (val) async {
                    final success = await settings.togglePricing(val);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(settings.errorMessage ?? 'Failed to update setting'),
                          backgroundColor: AppTheme.dangerColor,
                        ),
                      );
                    }
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                ),
              ),
              const Divider(height: 1, indent: 56),
              Consumer<SettingsProvider>(
                builder: (context, settings, _) => SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.indigoColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_shipping_rounded,
                        color: AppTheme.indigoColor, size: 20),
                  ),
                  title: const Text('Enable Vendors',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Track vendor assignments & costs',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  value: settings.vendorsEnabled,
                  activeTrackColor: AppTheme.indigoColor,
                  onChanged: (val) async {
                    final success = await settings.toggleVendors(val);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(settings.errorMessage ?? 'Failed to update setting'),
                          backgroundColor: AppTheme.dangerColor,
                        ),
                      );
                    }
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _SectionHeader(title: 'Product Attributes', color: AppTheme.accentColor),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.business_rounded,
                iconColor: AppTheme.primaryColor,
                title: 'Manage Companies',
                subtitle: 'Add or remove product brands/companies',
                onTap: () => _showManageListDialog(
                  context,
                  title: 'Manage Companies',
                  icon: Icons.business_rounded,
                  getItems: () => context.read<SettingsProvider>().companies,
                  onAdd: (name) => context.read<SettingsProvider>().addCompany(name),
                  onRemove: (name) => context.read<SettingsProvider>().removeCompany(name),
                ),
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                icon: Icons.straighten_rounded,
                iconColor: AppTheme.infoColor,
                title: 'Manage Sizes',
                subtitle: 'Add or remove product size options',
                onTap: () => _showManageListDialog(
                  context,
                  title: 'Manage Sizes',
                  icon: Icons.straighten_rounded,
                  getItems: () => context.read<SettingsProvider>().sizes,
                  onAdd: (name) => context.read<SettingsProvider>().addSize(name),
                  onRemove: (name) => context.read<SettingsProvider>().removeSize(name),
                ),
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                icon: Icons.location_on_rounded,
                iconColor: AppTheme.warningColor,
                title: 'Manage Locations',
                subtitle: 'Add or remove stock locations',
                onTap: () => _showManageListDialog(
                  context,
                  title: 'Manage Locations',
                  icon: Icons.location_on_rounded,
                  getItems: () => context.read<SettingsProvider>().locations,
                  onAdd: (name) => context.read<SettingsProvider>().addLocation(name),
                  onRemove: (name) => context.read<SettingsProvider>().removeLocation(name),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _SectionHeader(title: 'Administration', color: AppTheme.warningColor),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.people_rounded,
                iconColor: AppTheme.infoColor,
                title: 'User Management',
                subtitle: 'Add and manage staff users',
                onTap: () => Navigator.pushNamed(context, '/users'),
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                icon: Icons.shield_rounded,
                iconColor: AppTheme.warningColor,
                title: 'Staff Permissions',
                subtitle: 'Control what staff can access',
                onTap: () => Navigator.pushNamed(context, '/settings/permissions'),
              ),
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  if (!settings.vendorsEnabled) return const SizedBox.shrink();
                  return Column(
                    children: [
                      const Divider(height: 1, indent: 56),
                      _SettingsTile(
                        icon: Icons.local_shipping_rounded,
                        iconColor: AppTheme.indigoColor,
                        title: 'Manage Vendors',
                        subtitle: 'Add, edit and track vendor performance',
                        onTap: () => Navigator.pushNamed(context, '/vendors'),
                      ),
                    ],
                  );
                },
              ),
              if (user.isSuperAdmin) ...[
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.how_to_reg_rounded,
                  iconColor: AppTheme.warningColor,
                  title: 'Pending Approvals',
                  subtitle: 'Approve or reject new registrations',
                  onTap: () => Navigator.pushNamed(context, '/pending-approvals'),
                ),
              ],
            ],
          ),
        ],

        const SizedBox(height: 24),
        _SectionHeader(title: 'Data', color: AppTheme.successColor),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.file_upload_rounded,
              iconColor: AppTheme.infoColor,
              title: 'Import Data',
              onTap: () => Navigator.pushNamed(context, '/excel/import'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.file_download_rounded,
              iconColor: AppTheme.successColor,
              title: 'Export Data',
              onTap: () => Navigator.pushNamed(context, '/excel/export'),
            ),
          ],
        ),

        const SizedBox(height: 24),
        _SectionHeader(title: 'Legal', color: AppTheme.textSecondary),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.privacy_tip_rounded,
              iconColor: AppTheme.primaryColor,
              title: 'Privacy Policy',
              onTap: () => _launchUrl(context, 'https://smartshelfkart.com/privacy-policy.html'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.description_rounded,
              iconColor: AppTheme.indigoColor,
              title: 'Terms of Service',
              onTap: () => _launchUrl(context, 'https://smartshelfkart.com/terms.html'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.support_agent_rounded,
              iconColor: AppTheme.accentColor,
              title: 'Support',
              onTap: () => _launchUrl(context, 'https://smartshelfkart.com/support.html'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.delete_sweep_rounded,
              iconColor: AppTheme.dangerColor,
              title: 'Data Deletion',
              onTap: () => _launchUrl(context, 'https://smartshelfkart.com/data-deletion.html'),
            ),
          ],
        ),

        const SizedBox(height: 32),
        // Gradient logout button
        Container(
          decoration: BoxDecoration(
            gradient: AppTheme.dangerGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppTheme.coloredShadow(AppTheme.dangerColor),
          ),
          child: ElevatedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ),
      ],
    ),
    ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not open the link. Please try again later.'),
              backgroundColor: AppTheme.dangerColor,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: () => _launchUrl(context, url),
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong opening the link.'),
            backgroundColor: AppTheme.dangerColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showManageListDialog(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> Function() getItems,
    required Future<bool> Function(String) onAdd,
    required Future<bool> Function(String) onRemove,
  }) {
    final textCtrl = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final items = getItems();

          Future<void> handleAdd() async {
            final name = textCtrl.text.trim();
            if (name.isEmpty) return;
            final ok = await onAdd(name);
            if (ok) {
              textCtrl.clear();
              errorText = null;
            } else {
              errorText = '\'$name\' already exists';
            }
            setDialogState(() {});
          }

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textCtrl,
                          decoration: InputDecoration(
                            hintText: 'Enter name',
                            isDense: true,
                            errorText: errorText,
                          ),
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) {
                            if (errorText != null) {
                              setDialogState(() => errorText = null);
                            }
                          },
                          onSubmitted: (_) => handleAdd(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle_rounded,
                            color: AppTheme.primaryColor),
                        onPressed: handleAdd,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No items yet. Add one above.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text(items[i],
                              style: const TextStyle(fontSize: 14)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.dangerColor, size: 20),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: ctx,
                                builder: (c) => AlertDialog(
                                  title: const Text('Remove'),
                                  content: Text(
                                      'Remove "${items[i]}"? Existing products with this value won\'t be affected.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.dangerColor),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await onRemove(items[i]);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.dangerColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Edit Profile'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: user.email,
                  decoration: const InputDecoration(
                    labelText: 'Email (cannot be changed)',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                  readOnly: true,
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => ElevatedButton(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final ok = await auth.updateProfile(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                      );
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Profile updated!'
                                : auth.errorMessage ?? 'Failed to update'),
                            backgroundColor:
                                ok ? AppTheme.successColor : AppTheme.dangerColor,
                          ),
                        );
                        auth.clearError();
                      }
                    },
              child: auth.isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppTheme.dangerColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Delete Account'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.dangerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_rounded,
                              color: AppTheme.dangerColor, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'This action is permanent',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.dangerColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user.isAdmin
                            ? 'Your account and ALL company data (products, transactions, categories, staff accounts) will be permanently deleted.'
                            : 'Your account will be permanently removed. You will lose access to all company data.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Enter your password to confirm:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => ElevatedButton(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final ok = await auth.deleteAccount(passwordCtrl.text);
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (ok && context.mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(auth.errorMessage ?? 'Failed to delete account'),
                            backgroundColor: AppTheme.dangerColor,
                          ),
                        );
                        auth.clearError();
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
              child: auth.isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Delete Account'),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Change Password'),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPw,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: newPw,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'Min 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmPw,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v != newPw.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => ElevatedButton(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final ok = await auth.changePassword(currentPw.text, newPw.text);
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Password changed!'
                                : auth.errorMessage ?? 'Failed'),
                            backgroundColor:
                                ok ? AppTheme.successColor : AppTheme.dangerColor,
                          ),
                        );
                        auth.clearError();
                      }
                    },
              child: auth.isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Change'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey[500],
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500]))
          : null,
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    );
  }
}
