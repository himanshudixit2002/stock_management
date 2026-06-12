import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive.dart';
import '../../utils/dialogs.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/success_overlay.dart';

class CompanySwitcherScreen extends StatefulWidget {
  const CompanySwitcherScreen({super.key});

  @override
  State<CompanySwitcherScreen> createState() => _CompanySwitcherScreenState();
}

class _CompanySwitcherScreenState extends State<CompanySwitcherScreen> {
  bool _isSwitching = false;
  bool _loadingMeta = false;
  Map<String, String> _joinCodes = {};
  Set<String> _creatorCompanyIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSwitcherMeta());
  }

  Future<void> _loadSwitcherMeta() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final ids = <String>{user.companyId};
    for (final m in user.companyMemberships) {
      ids.add(m.companyId);
    }

    setState(() => _loadingMeta = true);
    try {
      final meta = await auth.getCompanySwitcherMeta(ids);
      if (!mounted) return;
      setState(() {
        _joinCodes = Map.from(meta.joinCodes);
        _creatorCompanyIds = Set.from(meta.creatorCompanyIds);
        _loadingMeta = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  String _shortDocId(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 5)}…${id.substring(id.length - 4)}';
  }

  Future<void> _switchCompany(
    BuildContext context,
    CompanyMembership membership,
  ) async {
    final auth = context.read<AuthProvider>();
    if (membership.companyId == auth.currentUser?.companyId) return;

    setState(() => _isSwitching = true);
    final ok = await auth.switchCompany(membership);
    if (!mounted) return;
    setState(() => _isSwitching = false);

    if (ok) {
      showSuccessOverlay(
        context,
        message: 'Switched to ${membership.companyName}',
      );
    } else {
      showErrorSnackBar(context, auth.errorMessage ?? 'Failed to switch');
    }
  }

  void _showCreateCompanyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Company'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Company Name',
            hintText: 'e.g. My Warehouse',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final auth = context.read<AuthProvider>();
              final m = await auth.createNewCompany(name);
              if (!mounted) return;
              if (m != null) {
                showSuccessSnackBar(context, 'Created "$name"');
                await _loadSwitcherMeta();
              } else {
                showErrorSnackBar(
                  context,
                  auth.errorMessage ?? 'Failed to create company',
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinCompanyDialog(BuildContext context) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Company'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a 6-character code. You can use either:',
                style: TextStyle(fontSize: 13, color: AppTheme.textSec(ctx)),
              ),
              const SizedBox(height: 10),
              Text(
                '• Company code — permanent; share with your team.\n'
                '• Invite code — expires in 7 days (from an admin).',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textPri(ctx),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. ABC123',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              if (code.length < 6) return;
              Navigator.pop(ctx);
              final auth = context.read<AuthProvider>();
              final ok = await auth.joinCompany(code);
              if (!mounted) return;
              if (ok) {
                showSuccessSnackBar(context, 'Joined company successfully');
                await _loadSwitcherMeta();
              } else {
                showErrorSnackBar(
                  context,
                  auth.errorMessage ?? 'Failed to join',
                );
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showInviteCodeDialog(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final code = await auth.generateInviteCode();
    if (!mounted) return;
    if (code == null) {
      showErrorSnackBar(
        context,
        auth.errorMessage ?? 'Failed to generate code',
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite code (7 days)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this time-limited code. It expires in 7 days. For a code that does not expire, use the company code on each workspace card.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                showSuccessSnackBar(ctx, 'Code copied to clipboard');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _ensureCodeForCompany(
    BuildContext context,
    String companyId,
  ) async {
    final auth = context.read<AuthProvider>();
    final code = await auth.ensurePermanentJoinCodeForCompany(companyId);
    if (!mounted) return;
    if (code != null) {
      showSuccessSnackBar(context, 'Company code created');
      await _loadSwitcherMeta();
    } else {
      showErrorSnackBar(
        context,
        auth.errorMessage ?? 'Could not create company code',
      );
    }
  }

  Future<void> _confirmRegeneratePermanentCode(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate company code?'),
        content: const Text(
          'The old company code will stop working. Anyone joining must use the new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final code = await auth.regeneratePermanentJoinCode();
    if (!mounted) return;
    if (code != null) {
      showSuccessSnackBar(context, 'New company code: $code');
      await _loadSwitcherMeta();
    } else {
      showErrorSnackBar(
        context,
        auth.errorMessage ?? 'Could not regenerate code',
      );
    }
  }

  void _confirmLeave(BuildContext context, CompanyMembership membership) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Company?'),
        content: Text(
          'Are you sure you want to leave "${membership.companyName}"? '
          'You will lose access to its data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final auth = context.read<AuthProvider>();
              final ok = await auth.leaveCompany(membership);
              if (!mounted) return;
              if (ok) {
                showSuccessSnackBar(
                  context,
                  'Left "${membership.companyName}"',
                );
                await _loadSwitcherMeta();
              } else {
                showErrorSnackBar(
                  context,
                  auth.errorMessage ?? 'Failed to leave',
                );
              }
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final companyName = user?.companyName ?? 'Unknown Company';
    final memberships = user?.companyMemberships ?? [];
    final activeId = user?.companyId ?? '';

    return AppScreenScaffold(
      icon: Icons.business_rounded,
      iconColor: AppTheme.indigoColor,
      title: 'Company',
      constrainWidth: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh codes',
          onPressed: _loadingMeta ? null : () => _loadSwitcherMeta(),
        ),
        if (user?.isAdmin == true)
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Invite code (7 days)',
            onPressed: () => _showInviteCodeDialog(context),
          ),
      ],
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.formMaxWidth(context),
              ),
              child: RefreshIndicator(
                color: AppTheme.primaryColor,
                onRefresh: _loadSwitcherMeta,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(
                    Responsive.horizontalPadding(context),
                  ),
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      memberships.length > 1
                          ? 'Your Companies'
                          : 'Current Company',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSec(context),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (memberships.isEmpty && user != null)
                      AnimatedListItem(
                        index: 0,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildCompanyCard(
                            context,
                            companyId: user.companyId,
                            name: companyName,
                            role: user.role,
                            isActive: true,
                            isCreator: _creatorCompanyIds.contains(
                              user.companyId,
                            ),
                            permanentCode: _joinCodes[user.companyId],
                            onTap: null,
                            onLeave: null,
                          ),
                        ),
                      ),
                    ...memberships.asMap().entries.map(
                      (entry) => AnimatedListItem(
                        index: entry.key,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildCompanyCard(
                            context,
                            companyId: entry.value.companyId,
                            name: entry.value.companyName,
                            role: entry.value.role,
                            isActive: entry.value.companyId == activeId,
                            isCreator: _creatorCompanyIds.contains(
                              entry.value.companyId,
                            ),
                            permanentCode: _joinCodes[entry.value.companyId],
                            onTap: entry.value.companyId == activeId
                                ? null
                                : () => _switchCompany(context, entry.value),
                            onLeave: entry.value.companyId == activeId
                                ? null
                                : () => _confirmLeave(context, entry.value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => _showCreateCompanyDialog(context),
                      icon: const Icon(Icons.add_business_rounded, size: 20),
                      label: const Text('Create New Company'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showJoinCompanyDialog(context),
                      icon: const Icon(Icons.group_add_rounded, size: 20),
                      label: const Text('Join Another Company'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Multi-company support lets you manage inventory across different businesses from a single account.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isSwitching || auth.isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: AppTheme.textPri(context).withValues(alpha: 0.18),
                child: Center(
                  child: GlassPanel(
                    borderRadius: 16,
                    useContentVariant: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Switching workspace…',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(
    BuildContext context, {
    required String companyId,
    required String name,
    required String role,
    required bool isActive,
    required bool isCreator,
    String? permanentCode,
    VoidCallback? onTap,
    VoidCallback? onLeave,
  }) {
    final code = permanentCode?.trim();
    final hasCode = code != null && code.isNotEmpty;

    return GlassPanel(
      useContentVariant: true,
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: isActive ? AppTheme.primaryGradient : null,
                      color: isActive
                          ? null
                          : AppTheme.textSec(context).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? Colors.white
                              : AppTheme.textPri(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isActive) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.successColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.successColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: role == 'admin'
                                    ? AppTheme.primaryColor.withValues(
                                        alpha: 0.1,
                                      )
                                    : AppTheme.textSec(
                                        context,
                                      ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                role == 'admin' ? 'Admin' : 'Staff',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: role == 'admin'
                                      ? AppTheme.primaryColor
                                      : AppTheme.textSec(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  if (isCreator && isActive && hasCode)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: AppTheme.textSec(context),
                        size: 22,
                      ),
                      onSelected: (v) {
                        if (v == 'regen') {
                          _confirmRegeneratePermanentCode(context);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'regen',
                          child: Text('Regenerate company code'),
                        ),
                      ],
                    ),
                  if (onLeave != null)
                    IconButton(
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: AppTheme.textSec(context),
                      ),
                      tooltip: 'Leave company',
                      onPressed: onLeave,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Support ID: ${_shortDocId(companyId)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSec(
                          context,
                        ).withValues(alpha: 0.85),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy full company ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: companyId));
                      showSuccessSnackBar(context, 'Company ID copied');
                    },
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
              if (hasCode) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Company code (permanent): $code',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy company code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        showSuccessSnackBar(context, 'Company code copied');
                      },
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ] else if (isCreator) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _ensureCodeForCompany(context, companyId),
                    icon: const Icon(Icons.vpn_key_rounded, size: 18),
                    label: const Text('Generate company code'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  'No company code yet. Ask the workspace creator to generate one.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
              if (!isActive && onTap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tap this card to switch workspace',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context).withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
