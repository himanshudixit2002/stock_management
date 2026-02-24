import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../config/theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/responsive.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = value.trim().toLowerCase();
      });
    });
  }

  List<UserModel> _filterUsers(List<UserModel> users) {
    if (_searchQuery.isEmpty) return users;
    return users.where((u) {
      return u.name.toLowerCase().contains(_searchQuery) ||
          u.email.toLowerCase().contains(_searchQuery) ||
          u.role.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.people_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('User Management'),
          ],
        ),
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: context.read<AuthProvider>().getAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShimmerLoading(itemCount: 4, layout: ShimmerLayout.listTile);
          }

          final allUsers = snapshot.data ?? [];

          if (allUsers.isEmpty) {
            return const Center(child: Text('No users found'));
          }

          final filteredUsers = _filterUsers(allUsers);

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
              child: Column(
            children: [
              // Search bar
              Padding(
                padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 12, Responsive.horizontalPadding(context), 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or role...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.inputFillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.inputBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.inputBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              // Results count
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filteredUsers.length} of ${allUsers.length} users',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              // User list
              Expanded(
                child: filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No users match "$_searchQuery"',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.delayed(const Duration(milliseconds: 500));
                        },
                        child: ListView.builder(
                        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final isCurrentUser =
                              user.uid == context.read<AuthProvider>().currentUser?.uid;

                          return AnimatedListItem(
                            index: index,
                            child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: user.isAdmin
                                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                    : AppTheme.accentColor.withValues(alpha: 0.1),
                                child: Icon(
                                  user.isAdmin
                                      ? Icons.admin_panel_settings
                                      : Icons.person,
                                  color: user.isAdmin
                                      ? AppTheme.primaryColor
                                      : AppTheme.accentColor,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    user.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (isCurrentUser) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'You',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.email),
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: user.isAdmin
                                          ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                          : AppTheme.accentColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      user.role.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: user.isAdmin
                                            ? AppTheme.primaryColor
                                            : AppTheme.accentColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: !isCurrentUser
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _confirmDeleteUser(context, user);
                                        } else {
                                          _changeRole(context, user, value);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (!user.isAdmin)
                                          const PopupMenuItem(
                                            value: 'admin',
                                            child: Text('Make Admin'),
                                          ),
                                        if (!user.isStaff)
                                          const PopupMenuItem(
                                            value: 'staff',
                                            child: Text('Make Staff'),
                                          ),
                                        if (user.isStaff) ...[
                                          const PopupMenuDivider(),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_rounded,
                                                    color: AppTheme.dangerColor, size: 20),
                                                const SizedBox(width: 8),
                                                Text('Remove User',
                                                    style: TextStyle(color: AppTheme.dangerColor)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : null,
                            ),
                          ),
                          );
                        },
                      ),
                      ),
              ),
            ],
          ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUserDialog(context),
        tooltip: 'Add Staff',
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
      ),
    );
  }

  void _changeRole(BuildContext context, UserModel user, String newRole) {
    bool isChanging = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Change Role'),
        content: Text(
          'Change ${user.name}\'s role to ${newRole.toUpperCase()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isChanging
                ? null
                : () async {
                    setDialogState(() => isChanging = true);
                    await context
                        .read<AuthProvider>()
                        .updateUserRole(user.uid, newRole);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      showSuccessOverlay(context, message: '${user.name} is now ${newRole.toUpperCase()}', popAfter: false);
                    }
                  },
            child: isChanging
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm'),
          ),
        ],
      ),
      ),
    );
  }

  void _confirmDeleteUser(BuildContext context, UserModel user) {
    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_remove_rounded,
                  color: AppTheme.dangerColor, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Remove User'),
          ],
        ),
        content: Text(
          'Remove ${user.name} (${user.email}) from your company?\n\n'
          'They will immediately lose access to all company data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isDeleting
                ? null
                : () async {
                    setDialogState(() => isDeleting = true);
                    final auth = context.read<AuthProvider>();
                    final ok = await auth.deleteStaffUser(user.uid);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      if (ok) {
                        showSuccessOverlay(context, message: '${user.name} has been removed', popAfter: false);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(auth.errorMessage ?? 'Failed to remove user'),
                            backgroundColor: AppTheme.dangerColor,
                          ),
                        );
                        auth.clearError();
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: isDeleting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Remove'),
          ),
        ],
      ),
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final adminPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Staff User'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: nameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person,
                  validator: (v) =>
                      v?.isEmpty ?? true ? 'Enter name' : null,
                ),
                CustomTextField(
                  controller: emailController,
                  label: 'Email',
                  prefixIcon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Enter email';
                    if (!v!.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                CustomTextField(
                  controller: passwordController,
                  label: 'Staff Password',
                  prefixIcon: Icons.lock,
                  obscureText: true,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Enter password';
                    if (v!.length < 6) return 'Min 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 4),
                const Text(
                  'Enter your admin password to confirm',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                CustomTextField(
                  controller: adminPasswordController,
                  label: 'Your Admin Password',
                  prefixIcon: Icons.shield,
                  obscureText: true,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Enter your password';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final success = await auth.addStaffUser(
                          name: nameController.text.trim(),
                          email: emailController.text.trim(),
                          password: passwordController.text,
                          adminPassword: adminPasswordController.text,
                        );

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (success) {
                            showSuccessOverlay(context, message: 'Staff user created!', popAfter: false);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(auth.errorMessage ?? 'Failed to create user'),
                                backgroundColor: AppTheme.dangerColor,
                              ),
                            );
                          }
                        }
                      },
                child: auth.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              );
            },
          ),
        ],
      ),
    );
  }
}
