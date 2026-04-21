import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Wraps a widget with MaterialApp and optional providers for widget testing.
Widget createTestApp({
  required Widget child,
  List<ChangeNotifierProvider> providers = const [],
}) {
  if (providers.isEmpty) {
    return MaterialApp(home: child);
  }
  return MultiProvider(
    providers: providers,
    child: MaterialApp(home: child),
  );
}

/// Pumps the widget and waits for all async operations to settle.
Future<void> pumpAndSettle(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}
