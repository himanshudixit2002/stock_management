import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/motion.dart';
import '../config/theme.dart';

const String _prefKey = 'feature_tour_completed';

/// What the signed-in user's shell actually shows, so the tour can describe it.
class FeatureTourNavigation {
  const FeatureTourNavigation({
    required this.tabLabels,
    required this.isWide,
    this.hasQuickActions = true,
    this.hasFeatureShortcuts = true,
  });

  /// The labels of the tabs this user has, in order.
  final List<String> tabLabels;

  /// True when the shell uses the side rail instead of the bottom bar.
  final bool isWide;

  final bool hasQuickActions;
  final bool hasFeatureShortcuts;
}

class FeatureTour extends StatefulWidget {
  final VoidCallback onComplete;
  final FeatureTourNavigation navigation;

  const FeatureTour({
    super.key,
    required this.onComplete,
    required this.navigation,
  });

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  @override
  State<FeatureTour> createState() => _FeatureTourState();
}

class _FeatureTourState extends State<FeatureTour>
    with SingleTickerProviderStateMixin {
  int _step = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  /// Recomputed on every build: the shell's tabs and Home's sections are
  /// still arriving when the tour first opens, and a list fixed at that moment
  /// skipped the Quick Actions step for anyone whose role loaded a beat later.
  List<_TourStep> get _steps => _stepsFor(widget.navigation);

  /// The tour only describes controls that exist for this user. It used to
  /// point at a raised "+" button the floating bar no longer has, at a search
  /// bar Home does not have, and at a Reports tab that Staff do not get.
  static List<_TourStep> _stepsFor(FeatureTourNavigation nav) {
    final tabs = nav.tabLabels;
    final tabList = switch (tabs.length) {
      0 => '',
      1 => tabs.first,
      _ => '${tabs.sublist(0, tabs.length - 1).join(', ')} and ${tabs.last}',
    };
    return [
      if (nav.hasQuickActions)
        const _TourStep(
          icon: Icons.bolt_rounded,
          title: 'Quick Actions',
          description:
              'The cards at the top of Home are your shortcuts. Choose them, '
              'and which sections Home shows, in Settings → Appearance & '
              'home → Customize Home.',
          alignment: Alignment(0, 0.35),
        ),
      if (nav.hasFeatureShortcuts)
        const _TourStep(
          icon: Icons.dashboard_customize_rounded,
          title: 'Find Everything',
          description:
              'Further down, Home groups the features you can use by area, '
              'such as Orders, Billing and Inventory.',
          alignment: Alignment(0, -0.1),
        ),
      if (tabs.length > 1)
        _TourStep(
          icon: Icons.navigation_rounded,
          title: 'Navigation',
          description: nav.isWide
              ? 'Switch between $tabList from the rail on the left.'
              : 'Switch between $tabList from the bar at the bottom.',
          alignment: nav.isWide ? Alignment.center : const Alignment(0, 0.35),
        ),
      const _TourStep(
        icon: Icons.search_rounded,
        title: 'Search',
        description:
            'Tap the search icon at the top of Home to find products, '
            'customers or a feature by name.',
        alignment: Alignment(0, -0.35),
      ),
      const _TourStep(
        icon: Icons.check_circle_rounded,
        title: 'All Done!',
        description:
            "You're all set. Explore the app and manage your inventory "
            'like a pro!',
        alignment: Alignment.center,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scaleAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutBack);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step >= _steps.length - 1) {
      _finish();
      return;
    }
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _step++);
      _fadeCtrl.forward();
    });
  }

  void _finish() async {
    await FeatureTour.markCompleted();
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (_step >= steps.length) _step = steps.length - 1;
    final step = steps[_step];
    final isLast = _step == steps.length - 1;
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {},
            child: Container(color: Colors.black.withValues(alpha: 0.7)),
          ),
          Align(
            alignment: step.alignment,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: reduceMotion(context)
                    ? const AlwaysStoppedAnimation<double>(1.0)
                    : Tween<double>(begin: 0.9, end: 1.0).animate(_scaleAnim),
                child: Container(
                width: size.width * 0.85,
                constraints: const BoxConstraints(maxWidth: 380),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSpotlight(context, step),
                    const SizedBox(height: 16),
                    Text(
                      step.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: List.generate(
                        steps.length,
                        (i) => Expanded(
                          child: Container(
                            height: 4,
                            margin: EdgeInsets.only(
                              right: i < steps.length - 1 ? 4 : 0,
                            ),
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? AppTheme.primaryColor
                                  : AppTheme.primaryColor.withValues(
                                      alpha: 0.15,
                                    ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (!isLast)
                          TextButton(
                            onPressed: _finish,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: AppTheme.textTer(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // "Next", not "Next (1/5)": the bar above already
                        // counts the steps, and the longer label pushed the
                        // row past a 360 px card at larger text sizes.
                        Flexible(
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              isLast ? 'Got it!' : 'Next',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              semanticsLabel: isLast
                                  ? 'Got it'
                                  : 'Next, step ${_step + 1} of ${steps.length}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSpotlight(BuildContext context, _TourStep step) {
    final badge = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGrad(context),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(step.icon, color: Colors.white, size: 28),
    );
    if (reduceMotion(context)) return badge;
    return badge
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 1.0,
          end: 1.08,
          duration: kPulseDuration,
          curve: Curves.easeInOut,
        );
  }
}

class _TourStep {
  final IconData icon;
  final String title;
  final String description;
  final Alignment alignment;

  const _TourStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.alignment,
  });
}
