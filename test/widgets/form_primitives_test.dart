import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/entity_picker_field.dart';
import 'package:stock_management/widgets/form_section.dart';

/// The stock screens themselves cannot be pumped: they sit behind a
/// `PermissionGate` that reads `AuthProvider`, and `AuthProvider` builds
/// `FirebaseAuth.instance` in a field initialiser — the same limitation the
/// repo already documents in `test/services/database_service_test.dart`.
///
/// So this covers the two primitives those screens were rebuilt on, with the
/// worst-case content they will actually be handed: long product names, an
/// error state, both themes, a narrow phone, and the app's text-scale ceiling.
Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) => MaterialApp(
  theme: brightness == Brightness.dark
      ? AppTheme.darkTheme
      : AppTheme.lightTheme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

const _longName =
    'A product with a deliberately very long name that will not fit on a line';

Widget _sampleForm() => Column(
  children: [
    FormSection(
      title: 'Product',
      subtitle: 'What is arriving',
      icon: Icons.inventory_2_rounded,
      children: [
        EntityPickerField(
          label: 'Product *',
          icon: Icons.inventory_2_rounded,
          value: _longName,
          detail: '42 pcs on hand',
          onTap: () {},
          onClear: () {},
        ),
      ],
    ),
    FormSection(
      title: 'Destination',
      subtitle: 'Where it lands, and who supplied it',
      icon: Icons.location_on_rounded,
      accent: AppTheme.infoColor,
      index: 1,
      children: [
        EntityPickerField(
          label: 'Location *',
          icon: Icons.location_on_rounded,
          onTap: () {},
          errorText: 'Please select a location',
        ),
      ],
    ),
  ],
);

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(360, 720),
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(child, brightness: brightness, textScale: textScale),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('FormSection', () {
    testWidgets('renders its title, subtitle and children', (tester) async {
      await pumpAt(tester, _sampleForm());
      expect(find.text('Product'), findsOneWidget);
      expect(find.text('What is arriving'), findsOneWidget);
      expect(find.byType(EntityPickerField), findsNWidgets(2));
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits a 360dp phone in ${brightness.name} mode', (
        tester,
      ) async {
        await pumpAt(tester, _sampleForm(), brightness: brightness);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives the 1.4x text-scale ceiling the app clamps to', (
      tester,
    ) async {
      await pumpAt(tester, _sampleForm(), textScale: 1.4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long trailing widget does not overflow the header', (
      tester,
    ) async {
      await pumpAt(
        tester,
        FormSection(
          title: 'A section title that is itself rather long',
          icon: Icons.settings_rounded,
          trailing: const Text('a trailing label that is also long'),
          children: const [SizedBox(height: 20)],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('EntityPickerField', () {
    testWidgets('shows the placeholder when nothing is selected', (
      tester,
    ) async {
      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Product',
          icon: Icons.inventory_2_rounded,
          placeholder: 'Tap to select a product',
          onTap: () {},
        ),
      );
      expect(find.text('Tap to select a product'), findsOneWidget);
    });

    testWidgets('shows the value and its detail line once selected', (
      tester,
    ) async {
      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Product',
          icon: Icons.inventory_2_rounded,
          value: 'Widget',
          detail: '42 pcs on hand',
          onTap: () {},
        ),
      );
      expect(find.text('Widget'), findsOneWidget);
      expect(find.text('42 pcs on hand'), findsOneWidget);
    });

    testWidgets('surfaces an error, which the hand-built fields could not', (
      tester,
    ) async {
      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Location',
          icon: Icons.location_on_rounded,
          onTap: () {},
          errorText: 'Please select a location',
        ),
      );
      expect(find.text('Please select a location'), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Product',
          icon: Icons.inventory_2_rounded,
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.byType(EntityPickerField));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('offers a clear affordance only once something is chosen', (
      tester,
    ) async {
      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Product',
          icon: Icons.inventory_2_rounded,
          onTap: () {},
          onClear: () {},
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await pumpAt(
        tester,
        EntityPickerField(
          label: 'Product',
          icon: Icons.inventory_2_rounded,
          value: 'Widget',
          onTap: () {},
          onClear: () {},
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}
