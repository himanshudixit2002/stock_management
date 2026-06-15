import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/motion.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../services/getting_started_cache.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';

/// A compact, dismissible "Getting Started" checklist surfaced on Home for the
/// people who set a workspace up (admins/owners).
///
/// Every step's completion is DERIVED from real data so it auto-updates and
/// never relies on a manual checkmark:
///   * Add your first product  → product count > 0
///   * Record a stock-in       → any stock-in transaction exists
///   * Invite a team member     → company user count > 1
///   * Enable billing           → billing toggle on
///
/// Only the *dismissed* flag is persisted (per company, via
/// [GettingStartedCache] — the Phase-1 shared_preferences pattern). The card
/// auto-hides once every step is complete, and is collapsible so it never
/// pushes the daily actions below the fold.
class GettingStartedCard extends StatefulWidget {
  const GettingStartedCard({super.key});

  @override
  State<GettingStartedCard> createState() => _GettingStartedCardState();
}

class _GettingStartedCardState extends State<GettingStartedCard> {
  final GettingStartedCache _cache = GettingStartedCache();

  bool _loaded = false;
  bool _dismissed = false;
  bool _expanded = true;
  String _loadedForCompany = '';
  Stream<List<UserModel>>? _usersStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDismissed());
  }

  Future<void> _loadDismissed() async {
    final companyId = context.read<AuthProvider>().currentUser?.companyId ?? '';
    final dismissed = await _cache.isDismissed(companyId);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _dismissed = dismissed;
      _loadedForCompany = companyId;
    });
  }

  Future<void> _dismiss(String companyId) async {
    HapticFeedback.selectionClick();
    setState(() => _dismissed = true);
    await _cache.setDismissed(companyId, true);
  }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) return const SizedBox.shrink();

    // Re-check dismissed state if the active company changed under us.
    if (_loaded && _loadedForCompany != user.companyId) {
      _loaded = false;
      _usersStream = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDismissed());
    }

    // Setup tasks (invite team, enable billing) are admin/owner concerns.
    if (!user.isAdmin || !_loaded || _dismissed) {
      return const SizedBox.shrink();
    }

    final hasProducts = context.select<ProductProvider, bool>(
      (p) => p.totalProducts > 0,
    );
    final hasStockIn = context.select<StockProvider, bool>(
      (s) => s.allTransactions.any((t) => t.type == TransactionType.stockIn),
    );
    final billingEnabled = context.select<BillingSettingsProvider, bool>(
      (b) => b.billingEnabled,
    );

    _usersStream ??= context.read<AuthProvider>().getAllUsers();

    return StreamBuilder<List<UserModel>>(
      stream: _usersStream,
      builder: (context, snapshot) {
        final hasTeam = (snapshot.data?.length ?? 1) > 1;

        final steps = <_ChecklistStep>[
          _ChecklistStep(
            label: 'Add your first product',
            icon: Icons.inventory_2_outlined,
            done: hasProducts,
            route: AppRoutes.addProduct,
          ),
          _ChecklistStep(
            label: 'Record a stock-in',
            icon: Icons.add_circle_outline_rounded,
            done: hasStockIn,
            route: AppRoutes.stockIn,
          ),
          _ChecklistStep(
            label: 'Invite a team member',
            icon: Icons.group_add_outlined,
            done: hasTeam,
            route: AppRoutes.userManagement,
          ),
          _ChecklistStep(
            label: 'Enable billing',
            icon: Icons.point_of_sale_outlined,
            done: billingEnabled,
            route: AppRoutes.billingSettings,
          ),
        ];

        final completed = steps.where((s) => s.done).length;
        // Auto-hide once everything is done — never nag a fully set-up team.
        if (completed == steps.length) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FadeSlideIn(
          child: GlassPanel(
            borderRadius: 16,
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, completed, steps.length, user.companyId),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final step in steps) _StepRow(step: step),
                      ],
                    ),
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    int completed,
    int total,
    String companyId,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.rocket_launch_rounded,
            size: 18,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Get started',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
              ),
              Text(
                '$completed of $total done',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSec(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _toggleExpanded,
          tooltip: _expanded ? 'Collapse' : 'Expand',
          visualDensity: VisualDensity.compact,
          icon: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.iconMute(context),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _dismiss(companyId),
          tooltip: 'Dismiss',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.close_rounded,
            size: 18,
            color: AppTheme.iconMute(context),
          ),
        ),
      ],
    );
  }
}

class _ChecklistStep {
  final String label;
  final IconData icon;
  final bool done;
  final String route;

  const _ChecklistStep({
    required this.label,
    required this.icon,
    required this.done,
    required this.route,
  });
}

class _StepRow extends StatelessWidget {
  final _ChecklistStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final done = step.done;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: done ? AppTheme.successColor : AppTheme.iconMute(context),
          ),
          const SizedBox(width: 12),
          Icon(
            step.icon,
            size: 18,
            color: done ? AppTheme.textTer(context) : AppTheme.primaryColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: done ? AppTheme.textTer(context) : AppTheme.textPri(context),
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!done)
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: AppTheme.iconMute(context),
            ),
        ],
      ),
    );

    if (done) return row;
    return Semantics(
      button: true,
      label: step.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, step.route),
          borderRadius: BorderRadius.circular(10),
          child: row,
        ),
      ),
    );
  }
}
