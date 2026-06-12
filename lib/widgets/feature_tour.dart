import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/motion.dart';
import '../config/theme.dart';

const String _prefKey = 'feature_tour_completed';

class FeatureTour extends StatefulWidget {
  final VoidCallback onComplete;

  const FeatureTour({super.key, required this.onComplete});

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

  static const _steps = <_TourStep>[
    _TourStep(
      icon: Icons.add_rounded,
      title: 'Quick Actions',
      description:
          'Tap the raised + button in the centre of the floating bar to open '
          'your daily actions — Stock In, Stock Out, Transfers, and more.',
      alignment: Alignment(0, 0.35),
    ),
    _TourStep(
      icon: Icons.dashboard_customize_rounded,
      title: 'Find Everything',
      description:
          'The Home screen groups every feature by category — Orders, Billing '
          'and Smart Inventory — so you always know where to look.',
      alignment: Alignment(0, -0.1),
    ),
    _TourStep(
      icon: Icons.bar_chart_rounded,
      title: 'Quick Stats',
      description:
          'See your inventory health at a glance — total products, low stock '
          'alerts, and today\'s transactions.',
      alignment: Alignment(0, -0.1),
    ),
    _TourStep(
      icon: Icons.navigation_rounded,
      title: 'Floating Navigation',
      description:
          'Switch between Home, Products, Reports, and Settings using the '
          'floating pill bar. Badges flag low or out-of-stock items.',
      alignment: Alignment(0, 0.35),
    ),
    _TourStep(
      icon: Icons.search_rounded,
      title: 'Search',
      description:
          'Tap the search bar at the top of Home to find any product, '
          'vendor, or transaction instantly.',
      alignment: Alignment(0, -0.35),
    ),
    _TourStep(
      icon: Icons.check_circle_rounded,
      title: 'All Done!',
      description:
          'You\'re all set. Explore the app and manage your inventory '
          'like a pro!',
      alignment: Alignment.center,
    ),
  ];

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
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;
    final size = MediaQuery.of(context).size;

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
                        _steps.length,
                        (i) => Expanded(
                          child: Container(
                            height: 4,
                            margin: EdgeInsets.only(
                              right: i < _steps.length - 1 ? 4 : 0,
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
                        FilledButton(
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
                            isLast
                                ? 'Got it!'
                                : 'Next (${_step + 1}/${_steps.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
        gradient: AppTheme.heroGradient,
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
