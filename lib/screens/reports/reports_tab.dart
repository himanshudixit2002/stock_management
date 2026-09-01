import 'package:flutter/material.dart';
import '../../widgets/deferred_screen_loader.dart';
import 'reports_screen.dart' deferred as reports_screen;

/// Tab wrapper for the Reports section.
///
/// The import is deferred. It used to be a plain import, which quietly undid
/// the deferred `reports` import in the router: this tab is part of the always
/// loaded home shell, so `ReportsScreen` — and through its analytics tab the
/// whole of `fl_chart` — was linked into the main bundle anyway. The home shell
/// only mounts a tab's body on first visit, so the load happens on the first
/// tap on Reports and is cached from then on.
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DeferredScreenLoader(
      future: reports_screen.loadLibrary(),
      builder: (_) => reports_screen.ReportsScreen(),
    );
  }
}
