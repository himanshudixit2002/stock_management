import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../utils/responsive.dart';
import '../../config/theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import '../../utils/dialogs.dart';
import '../../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _didAttemptSubmit = false;

  @override
  void dispose() {
    _nameController.dispose();
    _companyNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _didAttemptSubmit = true);
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      companyName: _companyNameController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    if (success && mounted) {
      showSuccessSnackBar(context, 'Account created successfully!');
      final user = authProvider.currentUser!;
      final companyId = user.companyId;
      context.read<ProductProvider>().initialize(companyId: companyId);
      context.read<CategoryProvider>().initialize(companyId: companyId);
      context.read<StockProvider>().initialize(companyId: companyId);
      context.read<VendorProvider>().initialize(companyId: companyId);
      await context.read<SettingsProvider>().initialize(companyId);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.formMaxWidth(context),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                    Responsive.horizontalPadding(context),
                  ),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _didAttemptSubmit
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Back button
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GlassPanel(
                              borderRadius: 14,
                              padding: EdgeInsets.zero,
                              useContentVariant: true,
                              child: IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 20,
                                ),
                                padding: const EdgeInsets.all(10),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          ScaleFadeIn(
                            child: GlassPanel(
                              borderRadius: 22,
                              padding: const EdgeInsets.all(14),
                              useContentVariant: true,
                              child: Image.asset(
                                'logo.png',
                                width: 56,
                                height: 56,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 120),
                            child: Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPri(context),
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 180),
                            child: Text(
                              'Enter your details below. You can update them later in settings.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textTer(context),
                                height: 1.35,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All fields are required.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSec(context),
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

                          Consumer<AuthProvider>(
                            builder: (context, auth, _) {
                              if (auth.errorMessage == null ||
                                  auth.errorMessage!.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.dangerColor.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.dangerColor.withValues(
                                      alpha: 0.25,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      color: AppTheme.dangerColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        auth.errorMessage!,
                                        style: TextStyle(
                                          color: AppTheme.dangerColor,
                                          fontSize: 13,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // Business info card
                          GlassPanel(
                            borderRadius: 16,
                            padding: const EdgeInsets.all(20),
                            useContentVariant: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.business_rounded,
                                        color: AppTheme.primaryColor,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Business Details',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPri(context),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Your company or store name and contact',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSec(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  controller: _companyNameController,
                                  label: 'Company / Business Name',
                                  hint: 'e.g. My Store, Acme Ltd',
                                  prefixIcon: Icons.storefront_rounded,
                                  autofillHints: const [
                                    AutofillHints.organizationName,
                                  ],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Company name is required';
                                    }
                                    return null;
                                  },
                                ),
                                CustomTextField(
                                  controller: _phoneController,
                                  label: 'Phone Number',
                                  hint: 'e.g. +1 234 567 8900',
                                  prefixIcon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Phone number is required';
                                    }
                                    final digits = value.replaceAll(
                                      RegExp(r'[^\d+]'),
                                      '',
                                    );
                                    if (digits.length < 10) {
                                      return 'Enter at least 10 digits';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Account info card
                          GlassPanel(
                            borderRadius: 16,
                            padding: const EdgeInsets.all(20),
                            useContentVariant: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.indigoColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.person_rounded,
                                        color: AppTheme.indigoColor,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Account Details',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPri(context),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Login credentials for this app',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSec(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  controller: _nameController,
                                  label: 'Full Name',
                                  hint: 'e.g. John Smith',
                                  prefixIcon: Icons.badge_rounded,
                                  autofillHints: const [AutofillHints.name],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Full name is required';
                                    }
                                    return null;
                                  },
                                ),
                                CustomTextField(
                                  controller: _emailController,
                                  label: 'Email Address',
                                  hint: 'e.g. you@company.com',
                                  prefixIcon: Icons.email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  validator: validateEmail,
                                ),
                                CustomTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hint: 'At least 6 characters',
                                  prefixIcon: Icons.lock_rounded,
                                  obscureText: !_showPassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  onChanged: (_) => setState(() {}),
                                  suffix: IconButton(
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size: 20,
                                      color: AppTheme.textSec(context),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showPassword = !_showPassword;
                                      });
                                    },
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (value.length < 6) {
                                      return 'Use at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                if (_passwordController.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _PasswordStrengthIndicator(
                                      password: _passwordController.text,
                                    ),
                                  ),
                                CustomTextField(
                                  controller: _confirmPasswordController,
                                  label: 'Confirm Password',
                                  hint: 'Type your password again',
                                  prefixIcon: Icons.lock_rounded,
                                  obscureText: !_showConfirmPassword,
                                  onChanged: (_) => setState(() {}),
                                  suffix: IconButton(
                                    icon: Icon(
                                      _showConfirmPassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size: 20,
                                      color: AppTheme.textSec(context),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showConfirmPassword =
                                            !_showConfirmPassword;
                                      });
                                    },
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please confirm your password';
                                    }
                                    if (value != _passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),
                                if (_confirmPasswordController
                                    .text
                                    .isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _confirmPasswordController.text ==
                                                  _passwordController.text
                                              ? Icons.check_circle_rounded
                                              : Icons.cancel_rounded,
                                          size: 16,
                                          color:
                                              _confirmPasswordController.text ==
                                                  _passwordController.text
                                              ? AppTheme.successColor
                                              : AppTheme.dangerColor,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _confirmPasswordController.text ==
                                                  _passwordController.text
                                              ? 'Passwords match'
                                              : 'Passwords do not match',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                _confirmPasswordController
                                                        .text ==
                                                    _passwordController.text
                                                ? AppTheme.successColor
                                                : AppTheme.dangerColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Register button with gradient
                          Semantics(
                            button: true,
                            label: 'Create account',
                            child: Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return ElevatedButton(
                                  onPressed:
                                      auth.isLoading ? null : _register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    disabledBackgroundColor:
                                        AppTheme.primaryColor.withValues(
                                      alpha: 0.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                    child: auth.isLoading
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Create Account',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                  );
                                },
                              ),
                          ),

                          const SizedBox(height: 24),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account? ',
                                style: TextStyle(
                                  color: AppTheme.textTer(context),
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  context.read<AuthProvider>().clearError();
                                  Navigator.pushReplacementNamed(
                                    context,
                                    AppRoutes.login,
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Sign in',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
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
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const _PasswordStrengthIndicator({required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = _getStrength(password);
    final label = strength == 0
        ? 'Too short'
        : strength == 1
        ? 'Weak'
        : strength == 2
        ? 'Medium'
        : 'Strong';
    final color = strength == 0
        ? AppTheme.dangerColor
        : strength == 1
        ? AppTheme.dangerColor
        : strength == 2
        ? AppTheme.warningColor
        : AppTheme.successColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: strength / 3),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    backgroundColor: AppTheme.inputFill(context),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  int _getStrength(String pw) {
    if (pw.length < 6) return 0;
    int score = 1;
    final hasUpper = pw.contains(RegExp(r'[A-Z]'));
    final hasLower = pw.contains(RegExp(r'[a-z]'));
    final hasDigit = pw.contains(RegExp(r'[0-9]'));
    final hasSpecial = pw.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));

    if (pw.length >= 8 && hasUpper && hasLower) score = 2;
    if (pw.length >= 8 && hasUpper && hasLower && hasDigit && hasSpecial) {
      score = 3;
    }
    return score;
  }
}
