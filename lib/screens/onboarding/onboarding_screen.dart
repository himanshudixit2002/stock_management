import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/settings_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/app_navigation.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  final _companyController = TextEditingController();
  final _sizeController = TextEditingController();

  final List<String> _addedLocations = [];
  final List<String> _addedCategories = [];
  final List<String> _addedCompanies = [];
  final List<String> _addedSizes = [];

  static const int _totalPages = 6;

  @override
  void dispose() {
    _pageController.dispose();
    _locationController.dispose();
    _categoryController.dispose();
    _companyController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) _goToPage(_currentPage + 1);
  }

  void _skip() => _goToPage(_totalPages - 1);

  Future<void> _addLocation() async {
    final name = _locationController.text.trim();
    if (name.isEmpty) return;

    final settings = context.read<SettingsProvider>();
    final success = await settings.addLocation(name);
    if (success && mounted) {
      setState(() => _addedLocations.add(name));
      _locationController.clear();
    }
  }

  Future<void> _addCategory() async {
    final name = _categoryController.text.trim();
    if (name.isEmpty) return;

    final user = context.read<AuthProvider>().currentUser;
    final categoryProvider = context.read<CategoryProvider>();
    final result = await categoryProvider.addCategory(
      name,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (result != null && mounted) {
      setState(() => _addedCategories.add(name));
      _categoryController.clear();
    }
  }

  Future<void> _addCompany() async {
    final name = _companyController.text.trim();
    if (name.isEmpty) return;

    final settings = context.read<SettingsProvider>();
    final success = await settings.addCompany(name);
    if (success && mounted) {
      setState(() => _addedCompanies.add(name));
      _companyController.clear();
    }
  }

  Future<void> _addSize() async {
    final name = _sizeController.text.trim();
    if (name.isEmpty) return;

    final settings = context.read<SettingsProvider>();
    final success = await settings.addSize(name);
    if (success && mounted) {
      setState(() => _addedSizes.add(name));
      _sizeController.clear();
    }
  }

  Future<void> _goToDashboard() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed_${user.companyId}', true);
    }
    if (mounted) {
      context.goAppRoute(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.formMaxWidth(context),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 1.0 / _totalPages,
                              end: (_currentPage + 1) / _totalPages,
                            ),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                            builder: (context, value, _) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 6,
                                  backgroundColor: AppTheme.dividerC(context),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_currentPage + 1} / $_totalPages',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppTheme.textSec(context),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (_currentPage < _totalPages - 1) ...[
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: _skip,
                            child: const Text('Skip'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const ClampingScrollPhysics(),
                      onPageChanged: (p) => setState(() => _currentPage = p),
                      children: [
                        _buildAnimatedPage(0, _buildWelcomePage()),
                        _buildAnimatedPage(1, _buildLocationPage()),
                        _buildAnimatedPage(2, _buildCategoryPage()),
                        _buildAnimatedPage(3, _buildCompanyPage()),
                        _buildAnimatedPage(4, _buildSizePage()),
                        _buildAnimatedPage(5, _buildCompletePage()),
                      ],
                    ),
                  ),
                  _buildDotIndicator(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedPage(int index, Widget child) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double value = 1.0;
        if (_pageController.position.haveDimensions) {
          final page = _pageController.page ?? _currentPage.toDouble();
          value = (1 - (page - index).abs()).clamp(0.0, 1.0);
        }
        return Opacity(
          opacity: value.clamp(0.5, 1.0),
          child: Transform.scale(scale: 0.9 + (0.1 * value), child: child),
        );
      },
      child: child,
    );
  }

  Widget _buildDotIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryColor
                : AppTheme.dividerC(context),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildWelcomePage() {
    final isSmall = MediaQuery.of(context).size.height < 700;
    final iconSize = isSmall ? 80.0 : 120.0;
    return Padding(
      padding: EdgeInsets.all(isSmall ? 24 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(isSmall ? 24 : 32),
              boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              size: isSmall ? 40 : 56,
              color: Colors.white,
            ),
          ),
          SizedBox(height: isSmall ? 24 : 40),
          Text(
            'Welcome!',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            "Let's set up your inventory in a few quick steps.",
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isSmall ? 24 : 40),
          ElevatedButton(
            onPressed: _nextPage,
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPage() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Icon(
            Icons.location_on_rounded,
            size: 48,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Add Your First Location',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Locations help you track where stock is stored.',
            style: TextStyle(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'New location name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSec(context),
            ),
          ),
          const SizedBox(height: 6),
          GlassPanel(
            useContentVariant: true,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Main Warehouse',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addLocation(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _addLocation,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_addedLocations.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _addedLocations
                  .map(
                    (l) => Chip(
                      label: Text(l),
                      avatar: const Icon(Icons.location_on_rounded, size: 16),
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.1,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_addedLocations.isEmpty ? 'Skip for Now' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPage() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.category_rounded, size: 48, color: AppTheme.indigoColor),
          const SizedBox(height: 16),
          Text(
            'Add Your First Category',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Categories help organize your products.',
            style: TextStyle(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'New category name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSec(context),
            ),
          ),
          const SizedBox(height: 6),
          GlassPanel(
            useContentVariant: true,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Electronics',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _addCategory,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_addedCategories.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _addedCategories
                  .map(
                    (c) => Chip(
                      label: Text(c),
                      avatar: const Icon(Icons.category_rounded, size: 16),
                      backgroundColor: AppTheme.indigoColor.withValues(
                        alpha: 0.1,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_addedCategories.isEmpty ? 'Skip for Now' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyPage() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.business_rounded, size: 48, color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          Text(
            'Add Companies / Brands',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Companies or brands help you organize products by manufacturer.',
            style: TextStyle(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'New company name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSec(context),
            ),
          ),
          const SizedBox(height: 6),
          GlassPanel(
            useContentVariant: true,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _companyController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Nike, Samsung',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCompany(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _addCompany,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_addedCompanies.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _addedCompanies
                  .map(
                    (c) => Chip(
                      label: Text(c),
                      avatar: const Icon(Icons.business_rounded, size: 16),
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.1,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_addedCompanies.isEmpty ? 'Skip for Now' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildSizePage() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.label_rounded, size: 48, color: AppTheme.warningColor),
          const SizedBox(height: 16),
          Text(
            'Add Sub-Categories',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Define sub-categories to group product variants like S, M, L or Type A, Type B.',
            style: TextStyle(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'New sub-category',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSec(context),
            ),
          ),
          const SizedBox(height: 6),
          GlassPanel(
            useContentVariant: true,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sizeController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Small, Medium, 42',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addSize(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _addSize,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_addedSizes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _addedSizes
                  .map(
                    (s) => Chip(
                      label: Text(s),
                      avatar: const Icon(Icons.label_rounded, size: 16),
                      backgroundColor: AppTheme.warningColor.withValues(
                        alpha: 0.1,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_addedSizes.isEmpty ? 'Skip for Now' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletePage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: AppTheme.successColor,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            "You're All Set!",
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your inventory is ready. You can always add more from Settings.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _goToDashboard,
            icon: const Icon(Icons.dashboard_rounded),
            label: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}