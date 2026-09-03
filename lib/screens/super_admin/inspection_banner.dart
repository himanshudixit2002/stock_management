import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/responsive.dart';

/// Enters [company] as a read-only observer and returns to the app shell.
///
/// Two pieces of state move together: the console records the inspection (and
/// audits it), and AuthProvider swaps in a synthetic view-only user bound to
/// that workspace. `app.dart` reads the first to decide what to render and the
/// second to decide which company to bind providers to.
void enterWorkspaceInspection(BuildContext context, CompanyModel company) {
  context.read<AuthProvider>().beginInspection(
    companyId: company.id,
    companyName: company.displayName,
  );
  context.read<SuperAdminProvider>().enterWorkspace(company);
}

void exitWorkspaceInspection(BuildContext context) {
  context.read<SuperAdminProvider>().exitWorkspace();
  context.read<AuthProvider>().endInspection();
}

/// A persistent strip shown above the whole app while inspecting a workspace.
///
/// Sits in the MaterialApp builder so it cannot be navigated away from — a
/// platform admin must never lose track of whose data they are looking at.
class InspectionBanner extends StatelessWidget {
  const InspectionBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final superAdmin = context.watch<SuperAdminProvider>();
    if (!superAdmin.isSuperAdmin || !superAdmin.isInspecting) return child;

    return Column(
      children: [
        Material(
          color: AppTheme.warningColor,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    size: 16,
                    color: AppTheme.onWarning(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Inspecting ${superAdmin.inspectCompanyName ?? ''} — '
                      'read-only',
                      style: TextStyle(
                        color: AppTheme.onWarning(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.onWarning(context),
                      // Not `compact`: that shrank the only way out of
                      // inspection mode below the 44px minimum touch target.
                      minimumSize: const Size(
                        Responsive.minTouchTargetSize,
                        Responsive.minTouchTargetSize,
                      ),
                    ),
                    onPressed: () {
                      // Pop back to the root so the console is not rendered
                      // underneath a stack of the tenant's routes.
                      Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst);
                      exitWorkspaceInspection(context);
                    },
                    child: const Text('Return to console'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
