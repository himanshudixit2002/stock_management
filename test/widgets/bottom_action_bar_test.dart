import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/widgets/bottom_action_bar.dart';

/// A screen shaped like Bulk Stock In: a list of rows above two buttons.
Widget _screen({required double maxWidth}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(title: const Text('Bulk Stock In')),
    body: ListView(
      children: const [SizedBox(height: 200, child: Text('Item 1'))],
    ),
    bottomNavigationBar: BottomActionBar(
      maxWidth: maxWidth,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 48, child: Text('Add Another Item')),
            SizedBox(height: 12),
            SizedBox(height: 52, child: Text('Submit All')),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _pumpAt(WidgetTester tester, Size size, Widget app) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

void main() {
  testWidgets('takes only its buttons\' height, leaving the body the rest', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800), _screen(maxWidth: 900));

    // 16 + 48 + 12 + 52 + 16. A Center in this slot took all 800, and the
    // list above was laid out at zero height — the blank Bulk Stock In.
    final bar = tester.getRect(find.byType(BottomActionBar));
    expect(bar.height, 144);
    expect(bar.bottom, 800);

    final body = tester.getRect(find.byType(ListView));
    expect(body.height, greaterThan(500));
    expect(find.text('Item 1').hitTestable(), findsOneWidget);
  });

  testWidgets('is centred and capped at its width on a wide screen', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800), _screen(maxWidth: 600));

    final button = tester.getRect(find.text('Submit All'));
    // 600 wide less the 16 padding either side, centred in 1200.
    expect(button.width, 568);
    expect(button.left, 316);
  });

  testWidgets('spans a phone', (tester) async {
    await _pumpAt(tester, const Size(360, 740), _screen(maxWidth: 600));

    expect(tester.getRect(find.text('Submit All')).width, 328);
    expect(find.text('Item 1').hitTestable(), findsOneWidget);
  });
}
