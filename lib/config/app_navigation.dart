import 'package:flutter/material.dart';

/// Helpers for [MaterialApp.onGenerateRoute] in [app.dart]. Pass route extras via
/// [pushAppRoute]’s [extra] parameter; they are delivered as [RouteSettings.arguments].
extension AppNavigation on BuildContext {
  Future<T?> pushAppRoute<T extends Object?>(String route, {Object? extra}) {
    return Navigator.of(this).pushNamed<T>(route, arguments: extra);
  }

  /// Replaces the entire stack with [route] (e.g. after logout or onboarding).
  void goAppRoute(String route) {
    Navigator.of(this).pushNamedAndRemoveUntil(route, (route) => false);
  }
}
