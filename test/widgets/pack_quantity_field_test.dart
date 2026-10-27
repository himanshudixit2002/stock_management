import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/pack_quantity_field.dart';

import '../helpers/test_helpers.dart';

Widget _host(Widget child) => createTestApp(
  child: Theme(
    data: AppTheme.lightTheme,
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

/// The packs field, then the loose-pieces field.
Finder _parts() => find.byType(TextField);

String _text(WidgetTester tester, int index) =>
    tester.widget<TextField>(_parts().at(index)).controller!.text;

void main() {
  testWidgets('splits the total into packs and loose pieces', (tester) async {
    final controller = TextEditingController(text: '23');
    await pumpAndSettle(
      tester,
      _host(PackQuantityField(controller: controller, unitsPerPack: 10)),
    );
    expect(_text(tester, 0), '2');
    expect(_text(tester, 1), '3');
    expect(find.textContaining('total 23 pcs'), findsOneWidget);
  });

  testWidgets('typing packs and pieces writes the total', (tester) async {
    final controller = TextEditingController();
    await pumpAndSettle(
      tester,
      _host(PackQuantityField(controller: controller, unitsPerPack: 10)),
    );
    await tester.enterText(_parts().at(0), '5');
    expect(controller.text, '50');
    await tester.enterText(_parts().at(1), '15');
    expect(controller.text, '65');
    // Not re-split under the cursor while the person is still typing.
    expect(_text(tester, 1), '15');
  });

  testWidgets('a total set from outside is split again', (tester) async {
    final controller = TextEditingController(text: '10');
    await pumpAndSettle(
      tester,
      _host(PackQuantityField(controller: controller, unitsPerPack: 10)),
    );
    controller.text = '37';
    await tester.pump();
    expect(_text(tester, 0), '3');
    expect(_text(tester, 1), '7');
  });

  testWidgets('a new pack size redraws the split, keeping the total', (
    tester,
  ) async {
    final controller = TextEditingController(text: '24');
    Widget field(int perPack) =>
        _host(PackQuantityField(controller: controller, unitsPerPack: perPack));
    await pumpAndSettle(tester, field(10));
    expect(_text(tester, 0), '2');
    await pumpAndSettle(tester, field(12));
    expect(_text(tester, 0), '2');
    expect(_text(tester, 1), '');
    expect(controller.text, '24');
  });

  testWidgets('without a pack it is one plain field', (tester) async {
    final controller = TextEditingController(text: '7');
    await pumpAndSettle(
      tester,
      _host(PackQuantityField(controller: controller, baseUnit: 'kg')),
    );
    expect(_parts(), findsOneWidget);
    await tester.enterText(_parts(), '9');
    expect(controller.text, '9');
  });
}
