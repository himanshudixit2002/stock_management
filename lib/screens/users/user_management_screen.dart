import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/role_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/user_model.dart';
import '../../models/role_model.dart';
import '../../models/workspace_member_model.dart';
import '../../config/theme.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/responsive.dart';
import '../../utils/dialogs.dart';
import '../../utils/validators.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../utils/debouncer.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _searchDebounce = Debouncer();
  int _usersStreamEpoch = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce.run(() {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
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

  List<WorkspaceMember> _filterMembers(List<WorkspaceMember> members) {
    if (_searchQuery.isEmpty) return members;
    return members.where((m) {
      return m.name.toLowerCase().contains(_searchQuery) ||
          m.email.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  /// The workspace's user docs together with its member docs.
  ///
  /// A user doc is only readable here while its active workspace is this one,
  /// so someone who has switched to another workspace is missing from the
  /// user list, yet still holds a member doc and can switch back at any time.
  /// The member docs are the only way to see, and remove, them. Users drive
  /// the stream (and its errors). Members are best-effort, so a failure there
  /// only hides that section.
  Stream<_Roster> _rosterStream(AuthProvider auth) {
    late final StreamController<_Roster> controller;
    StreamSubscription<List<UserModel>>? usersSub;
    StreamSubscription<List<WorkspaceMember>>? membersSub;
    List<UserModel>? users;
    var members = const <WorkspaceMember>[];
    void emit() {
      final u = users;
      if (u != null) controller.add(_Roster(u, members));
    }

    controller = StreamController<_Roster>(
      onListen: () {
        usersSub = auth.getAllUsers().listen((u) {
          users = u;
          emit();
        }, onError: controller.addError);
        membersSub = auth.getWorkspaceMembers().listen((m) {
          members = m;
          emit();
        }, onError: (Object _) {});
      },
      onCancel: () async {
        await usersSub?.cancel();
        await membersSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final companyId = auth.currentUser?.companyId ?? '';
    final companyName = auth.currentUser?.companyName ?? '';
    // The company doc's adminUid is who actually owns the workspace, and the
    // security rules refuse anyone else's attempt to remove or change them.
    // The owner's user doc reads role 'admin' like any other admin's.
    final ownerUid = context.watch<SettingsProvider>().company?.adminUid ?? '';

    return PermissionGate(
      permission: AppPermissions.manageUsers,
      featureName: 'User Management',
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppBarTitleRow(
                icon: Icons.people_rounded,
                color: AppTheme.primaryColor,
                title: 'User Management',
              ),
              if (companyName.isNotEmpty)
                Text(
                  companyName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSec(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: StreamBuilder<_Roster>(
            key: ValueKey<String>('$companyId-$_usersStreamEpoch'),
            stream: companyId.isEmpty
                ? Stream.value(const _Roster([], []))
                : _rosterStream(auth),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const ShimmerLoading(
                  itemCount: 4,
                  layout: ShimmerLayout.listTile,
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: AppTheme.dangerColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load users',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _usersStreamEpoch++),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allUsers = snapshot.data?.users ?? const <UserModel>[];
              final elsewhere =
                  snapshot.data?.elsewhere ?? const <WorkspaceMember>[];

              if (allUsers.isEmpty && elsewhere.isEmpty) {
                return EmptyStateWidget(
                  icon: Icons.people_outline_rounded,
                  title: 'No users yet',
                  subtitle: 'Add your first staff member to get started.',
                  buttonText: 'Add Staff',
                  onButtonPressed: () => _showAddUserDialog(context),
                );
              }

              final filteredUsers = _filterUsers(allUsers);
              final filteredElsewhere = _filterMembers(elsewhere);
              final elsewhereRows = filteredElsewhere.isEmpty
                  ? 0
                  : filteredElsewhere.length + 1;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: Column(
                    children: [
                      // Search bar
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          12,
                          Responsive.horizontalPadding(context),
                          8,
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search by name, email, or role...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Clear search',
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
                            fillColor: AppTheme.inputFill(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      // Results count
                      if (_searchQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 2,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${filteredUsers.length + filteredElsewhere.length} '
                              'of ${allUsers.length + elsewhere.length} users',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          ),
                        ),
                      // User list
                      Expanded(
                        child: filteredUsers.isEmpty &&
                                filteredElsewhere.isEmpty
                            ? EmptyStateWidget(
                                icon: Icons.search_off_rounded,
                                title: 'No matches',
                                subtitle: 'No users match "$_searchQuery"',
                              )
                            : RefreshIndicator(
                                color: AppTheme.primaryColor,
                                onRefresh: () async {
                                  await Future.delayed(
                                    const Duration(milliseconds: 300),
                                  );
                                  // Stream auto-refreshes; delay provides visual feedback
                                },
                                child: ListView.builder(
                                  padding: EdgeInsets.all(
                                    Responsive.horizontalPadding(context),
                                  ),
                                  itemCount:
                                      filteredUsers.length + elsewhereRows,
                                  itemBuilder: (context, index) {
                                    if (index >= filteredUsers.length) {
                                      final i = index - filteredUsers.length;
                                      return i == 0
                                          ? _buildElsewhereHeader(context)
                                          : _buildElsewhereMember(
                                              context,
                                              filteredElsewhere[i - 1],
                                              companyName: companyName,
                                              ownerUid: ownerUid,
                                            );
                                    }
                                    final user = filteredUsers[index];
                                    final isCurrentUser =
                                        user.uid ==
                                        context
                                            .read<AuthProvider>()
                                            .currentUser
                                            ?.uid;
                                    // Nobody can remove or re-role the owner.
                                    // Until the company doc loads, fall back
                                    // to whoever holds the Owner role.
                                    final isWorkspaceOwner = ownerUid.isNotEmpty
                                        ? user.uid == ownerUid
                                        : user.isOwner;

                                    final card = Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 8,
                                      ),
                                      child: GlassCard(
                                          borderRadius: 14,
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: user.isAdmin
                                                  ? AppTheme.primaryColor
                                                        .withValues(alpha: 0.1)
                                                  : AppTheme.accentColor
                                                        .withValues(alpha: 0.1),
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
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (isCurrentUser) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppTheme.primaryColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'You',
                                                      style: TextStyle(
                                                        color: AppTheme.surface(
                                                          context,
                                                        ),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(user.email),
                                                Builder(
                                                  builder: (_) {
                                                    final roleProvider = context
                                                        .watch<RoleProvider>();
                                                    final role = roleProvider
                                                        .getRoleById(
                                                          user.roleId,
                                                        );
                                                    final roleName =
                                                        role?.name ??
                                                        user.role.toUpperCase();
                                                    final isPrivileged =
                                                        user.isAdmin ||
                                                        user.roleId ==
                                                            RoleModel
                                                                .managerRoleId;
                                                    return Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isPrivileged
                                                            ? AppTheme
                                                                  .primaryColor
                                                                  .withValues(
                                                                    alpha: 0.1,
                                                                  )
                                                            : AppTheme
                                                                  .accentColor
                                                                  .withValues(
                                                                    alpha: 0.1,
                                                                  ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        roleName.toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isPrivileged
                                                              ? AppTheme
                                                                    .primaryColor
                                                              : AppTheme
                                                                    .accentColor,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                            isThreeLine: true,
                                            trailing:
                                                !isCurrentUser &&
                                                    !isWorkspaceOwner
                                                ? PopupMenuButton<String>(
                                                    onSelected: (value) {
                                                      if (value == 'delete') {
                                                        _confirmRemoveMember(
                                                          context,
                                                          uid: user.uid,
                                                          name: user.name,
                                                          email: user.email,
                                                          companyName:
                                                              companyName,
                                                          activeHere: true,
                                                        );
                                                      } else if (value ==
                                                          'assign_role') {
                                                        _showRoleAssignSheet(
                                                          context,
                                                          user,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem(
                                                        value: 'assign_role',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .badge_rounded,
                                                              size: 20,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Assign Role'),
                                                          ],
                                                        ),
                                                      ),
                                                      if (!user.isOwner) ...[
                                                        const PopupMenuDivider(),
                                                        PopupMenuItem(
                                                          value: 'delete',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .delete_rounded,
                                                                color: AppTheme
                                                                    .dangerColor,
                                                                size: 20,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Text(
                                                                'Remove User',
                                                                style: TextStyle(
                                                                  color: AppTheme
                                                                      .dangerColor,
                                                                ),
                                                              ),
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
                                    // Cap entrance animations for large lists.
                                    return index < 15
                                        ? AnimatedListItem(
                                            index: index,
                                            child: card,
                                          )
                                        : card;
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
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddUserDialog(context),
          tooltip: 'Add Staff',
          icon: const Icon(Icons.person_add),
          label: const Text('Add Staff'),
        ),
      ),
    );
  }

  void _showRoleAssignSheet(BuildContext context, UserModel user) {
    String? selectedRoleId = user.roleId.isNotEmpty ? user.roleId : null;
    bool isChanging = false;
    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final roles = context.read<RoleProvider>().roles;
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) => Container(
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerC(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.badge_rounded,
                          color: AppTheme.accentColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Assign Role',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'Select a role for ${user.name}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: selectedRoleId,
                  onChanged: (v) => setSheetState(() => selectedRoleId = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: roles.map(
                      (role) => RadioListTile<String>(
                        value: role.id,
                        title: Text(
                          role.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          role.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                        secondary: Text(
                          '${role.enabledCount}/${role.totalCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppTheme.dividerC(context)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppTheme.textSec(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (isChanging || selectedRoleId == null)
                              ? null
                              : () async {
                                  setSheetState(() => isChanging = true);
                                  final auth = context.read<AuthProvider>();
                                  final ok = await auth.updateUserRoleId(
                                    user.uid,
                                    selectedRoleId!,
                                  );
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                  if (!ok) {
                                    if (context.mounted) {
                                      showErrorSnackBar(
                                        context,
                                        auth.errorMessage ??
                                            'Could not change the role.',
                                      );
                                    }
                                    return;
                                  }
                                  if (context.mounted) {
                                    setState(() => _usersStreamEpoch++);
                                    final roleName = roles
                                        .firstWhere(
                                          (r) => r.id == selectedRoleId,
                                          orElse: () => roles.first,
                                        )
                                        .name;
                                    showSuccessOverlay(
                                      context,
                                      message: '${user.name} is now $roleName',
                                      popAfter: false,
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: isChanging
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Assign',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Header over the members who are not using this workspace right now.
  Widget _buildElsewhereHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not using this workspace right now',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSec(context),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'They still hold access here and can switch back at any time.',
            style: TextStyle(fontSize: 12, color: AppTheme.textTer(context)),
          ),
        ],
      ),
    );
  }

  /// A member whose user doc does not point at this workspace: they are using
  /// another one, or their account record is gone. Their role and permissions
  /// cannot be edited from here, only their membership removed, and not even
  /// that for the owner.
  Widget _buildElsewhereMember(
    BuildContext context,
    WorkspaceMember member, {
    required String companyName,
    required String ownerUid,
  }) {
    final isWorkspaceOwner = ownerUid.isNotEmpty
        ? member.uid == ownerUid
        : member.roleId == RoleModel.ownerRoleId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 14,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.textSec(context).withValues(alpha: 0.1),
            child: Icon(
              Icons.swap_horiz_rounded,
              color: AppTheme.textSec(context),
            ),
          ),
          title: Text(
            member.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            member.email.isNotEmpty && member.email != member.displayName
                ? member.email
                : 'Not using this workspace right now',
          ),
          trailing: isWorkspaceOwner
              ? null
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmRemoveMember(
                        context,
                        uid: member.uid,
                        name: member.displayName,
                        email: member.email,
                        companyName: companyName,
                        activeHere: false,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_rounded,
                            color: AppTheme.dangerColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Remove User',
                            style: TextStyle(color: AppTheme.dangerColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Confirms, then removes [uid] from this workspace only.
  ///
  /// [activeHere] says whether this is the member's active workspace, which
  /// changes what removal does to their open session.
  void _confirmRemoveMember(
    BuildContext context, {
    required String uid,
    required String name,
    required String email,
    required String companyName,
    required bool activeHere,
  }) {
    bool isDeleting = false;
    final who = email.isNotEmpty && email != name ? '$name ($email)' : name;
    final where = companyName.isNotEmpty ? companyName : 'this workspace';
    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerC(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_remove_rounded,
                        color: AppTheme.dangerColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'Remove User',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.dangerColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.surface(context),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.dangerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        activeHere
                            ? 'Remove $who from $where?\n\n'
                                  'They lose access to its data at once. If '
                                  'they have the app open, it takes them out of '
                                  'this workspace and tells them why. Their '
                                  'account and any other workspaces they belong '
                                  'to are not affected.\n\n'
                                  'The company code will not let them back in. '
                                  'To take them back later, send them a new '
                                  'invite.'
                            : 'Remove $who from $where?\n\n'
                                  'They are not using this workspace right now, '
                                  'so nothing changes on their screen, but they '
                                  'can no longer switch back into it.\n\n'
                                  'To take them back later, send them a new '
                                  'invite.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPri(context),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                color: AppTheme.dividerC(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppTheme.textSec(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isDeleting
                                ? null
                                : () async {
                                    setSheetState(() => isDeleting = true);
                                    final auth = context.read<AuthProvider>();
                                    final ok = await auth.removeMember(
                                      uid: uid,
                                      name: name,
                                      email: email,
                                    );
                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }
                                    if (context.mounted) {
                                      if (ok) {
                                        setState(() => _usersStreamEpoch++);
                                        showSuccessOverlay(
                                          context,
                                          message: '$name has been removed',
                                          popAfter: false,
                                        );
                                      } else {
                                        showErrorSnackBar(
                                          context,
                                          auth.errorMessage ??
                                              'Failed to remove user',
                                        );
                                        auth.clearError();
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.dangerColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: isDeleting
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.surface(context),
                                    ),
                                  )
                                : const Text(
                                    'Remove',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    String selectedRoleId = RoleModel.staffRoleId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerC(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: AppTheme.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Add Staff',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          validator: validateEmail,
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
                        StatefulBuilder(
                          builder: (ctx, setLocalState) {
                            final roles = ctx.watch<RoleProvider>().roles;
                            return DropdownButtonFormField<String>(
                              initialValue: selectedRoleId,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                prefixIcon: Icon(Icons.badge_rounded),
                              ),
                              items: roles
                                  .map(
                                    (r) => DropdownMenuItem(
                                      value: r.id,
                                      child: Text(r.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setLocalState(() => selectedRoleId = v);
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.04,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Enter your admin password to verify this action',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        CustomTextField(
                          controller: adminPasswordController,
                          label: 'Your Admin Password',
                          prefixIcon: Icons.shield,
                          obscureText: true,
                          validator: (v) {
                            if (v?.isEmpty ?? true) {
                              return 'Enter your password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.dividerC(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: AppTheme.textSec(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Consumer<AuthProvider>(
                                builder: (context, auth, _) => ElevatedButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          final success = await auth
                                              .addStaffUser(
                                                name: nameController.text
                                                    .trim(),
                                                email: emailController.text
                                                    .trim(),
                                                password:
                                                    passwordController.text,
                                                adminPassword:
                                                    adminPasswordController
                                                        .text,
                                                roleId: selectedRoleId,
                                              );

                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                            if (success) {
                                              setState(
                                                () => _usersStreamEpoch++,
                                              );
                                              showSuccessOverlay(
                                                context,
                                                message: 'Staff user created!',
                                                popAfter: false,
                                              );
                                            } else {
                                              showErrorSnackBar(
                                                context,
                                                auth.errorMessage ??
                                                    'Failed to create user',
                                              );
                                            }
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Create Staff',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What User Management lists: the workspace's user docs, plus the members
/// whose user doc is not readable here because they are not using this
/// workspace right now.
class _Roster {
  const _Roster(this.users, List<WorkspaceMember> members)
    : _members = members;

  final List<UserModel> users;
  final List<WorkspaceMember> _members;

  List<WorkspaceMember> get elsewhere {
    final here = {for (final u in users) u.uid};
    return _members.where((m) => !here.contains(m.uid)).toList();
  }
}
