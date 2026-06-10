import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// Wraps a child widget and only shows it when the user has the required permission.
/// Shows a fallback (or a default "no permission" scaffold) otherwise.
class PermissionGate extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;
  final String? featureName;

  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && user.hasPermission(permission)) {
      return child;
    }
    return fallback ?? _NoPermissionScaffold(featureName: featureName);
  }
}

/// Checks ANY of the listed permissions and shows the child if at least one passes.
class AnyPermissionGate extends StatelessWidget {
  final List<String> permissions;
  final Widget child;
  final Widget? fallback;
  final String? featureName;

  const AnyPermissionGate({
    super.key,
    required this.permissions,
    required this.child,
    this.fallback,
    this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && user.hasAnyPermission(permissions)) {
      return child;
    }
    return fallback ?? _NoPermissionScaffold(featureName: featureName);
  }
}

class _NoPermissionScaffold extends StatelessWidget {
  final String? featureName;
  const _NoPermissionScaffold({this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(featureName ?? 'Access Denied')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 48,
                  color: AppTheme.dangerColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Permission',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPri(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have permission to access'
                '${featureName != null ? ' $featureName' : ' this feature'}.\n'
                'Contact your administrator to request access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textTer(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline visibility helper: hides its child if the user lacks the permission.
class PermissionVisible extends StatelessWidget {
  final String permission;
  final Widget child;

  const PermissionVisible({
    super.key,
    required this.permission,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(permission)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
