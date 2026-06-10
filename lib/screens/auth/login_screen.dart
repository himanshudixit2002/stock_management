import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/glass_panel.dart';
import '../../utils/dialogs.dart';
import '../../utils/validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final resetFormKey = GlobalKey<FormState>();
    bool isSending = false;

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
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
                            Icons.lock_reset_rounded,
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Reset Password',
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Form(
                      key: resetFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter your email address and we\'ll send you a link to reset your password.',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: resetEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: validateEmail,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isSending
                                      ? null
                                      : () => Navigator.pop(sheetCtx),
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
                                child: ElevatedButton(
                                  onPressed: isSending
                                      ? null
                                      : () async {
                                          if (!resetFormKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          setSheetState(() => isSending = true);
                                          final authProvider = context
                                              .read<AuthProvider>();
                                          final success = await authProvider
                                              .resetPassword(
                                                resetEmailController.text
                                                    .trim(),
                                              );
                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                          }
                                          if (mounted) {
                                            if (success) {
                                              showSuccessSnackBar(
                                                context,
                                                'Password reset email sent! Check your inbox.',
                                              );
                                            } else {
                                              showErrorSnackBar(
                                                context,
                                                authProvider.errorMessage ??
                                                    'Failed to send reset email',
                                              );
                                            }
                                            authProvider.clearError();
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
                                  child: isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Send Reset Link',
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                          const SizedBox(height: 28),

                          GlassPanel(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(16),
                            useContentVariant: true,
                            child: Image.asset(
                              'logo.png',
                              width: 64,
                              height: 64,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPri(context),
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to manage your inventory',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textTer(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Error message
                          Consumer<AuthProvider>(
                            builder: (context, auth, _) {
                              if (auth.errorMessage != null) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.dangerColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.dangerColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppTheme.dangerColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          auth.errorMessage!,
                                          style: const TextStyle(
                                            color: AppTheme.dangerColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),

                          // Form fields in a card
                          GlassPanel(
                            borderRadius: 16,
                            padding: const EdgeInsets.all(20),
                            useContentVariant: true,
                            child: Column(
                              children: [
                                CustomTextField(
                                  controller: _emailController,
                                  label: 'Email Address',
                                  hint: 'Enter your email',
                                  prefixIcon: Icons.email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  validator: validateEmail,
                                ),

                                CustomTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hint: 'Enter your password',
                                  prefixIcon: Icons.lock_rounded,
                                  obscureText: !_showPassword,
                                  autofillHints: const [AutofillHints.password],
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
                                      return 'Please enter your password';
                                    }
                                    if (value.length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () =>
                                        _showForgotPasswordDialog(),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Login button
                          Container(
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: AppTheme.coloredShadow(
                                AppTheme.primaryColor,
                              ),
                            ),
                            child: Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                return ElevatedButton(
                                  onPressed: auth.isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                  ),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Sign In'),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: AppTheme.dividerStrongC(context),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'or',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textTer(context),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: AppTheme.dividerStrongC(context),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
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
                                    AppRoutes.register,
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 36),
                                ),
                                child: const Text(
                                  'Create Account',
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
