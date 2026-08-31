import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/models/billing_settings_model.dart';
import 'package:stock_management/providers/billing_settings_provider.dart';
import 'package:stock_management/utils/currency.dart';

/// A stand-in for the real provider so the test needs no Firebase.
class _FakeBillingSettings extends BillingSettingsProvider {
  @override
  var settings = const BillingSettings();

  void setSymbol(String symbol) {
    settings = settings.copyWith(currencySymbol: symbol);
    notifyListeners();
  }
}

void main() {
  Future<void> pumpWith(WidgetTester tester, _FakeBillingSettings provider) {
    return tester.pumpWidget(
      ChangeNotifierProvider<BillingSettingsProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Text(
              Money.of(context, 1234.5),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Money.of reads the configured symbol from billing settings',
      (tester) async {
    final provider = _FakeBillingSettings()..setSymbol(r'$');
    await pumpWith(tester, provider);
    expect(find.text(r'$1,234.50'), findsOneWidget);
  });

  testWidgets('Money.of falls back when no symbol is configured',
      (tester) async {
    final provider = _FakeBillingSettings()..setSymbol('');
    await pumpWith(tester, provider);
    expect(find.text('${Money.fallbackSymbol}1,234.50'), findsOneWidget);
  });

  testWidgets('changing the currency repaints screens that display money',
      (tester) async {
    final provider = _FakeBillingSettings()..setSymbol(r'$');
    await pumpWith(tester, provider);
    expect(find.text(r'$1,234.50'), findsOneWidget);

    provider.setSymbol('€');
    await tester.pump();

    expect(find.text('€1,234.50'), findsOneWidget);
    expect(find.text(r'$1,234.50'), findsNothing);
  });
}
