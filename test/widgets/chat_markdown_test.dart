import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/screens/ai/widgets/chat_markdown.dart';

const _wideTable = '''
Here is what you should reorder.

| Product | Stock | Reorder point | Days cover | Unit price | Vendor |
| :--- | ---: | ---: | ---: | ---: | :--- |
| A very long product name here | 120 | 40 | 29 | 45.00 | Acme Supplies Ltd |
| Another long product name | 12 | 30 | 4 | 199.00 | Globex Distribution |

Order the second one first.
''';

Widget _host(String md, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(child: ChatMarkdown(text: md)),
      ),
    );

Finder get _horizontalScrollables => find.byWidgetPredicate((w) =>
    w is Scrollable &&
    (w.axisDirection == AxisDirection.right ||
        w.axisDirection == AxisDirection.left));

void main() {
  group('a wide table', () {
    testWidgets('has exactly one horizontal scroller, and it owns the overflow',
        (tester) async {
      // The bug this pins: the renderer used to wrap flutter_markdown's own
      // table scroll view in a second one. The inner scroller is the one that
      // receives the drag, and being handed unbounded width it had nothing to
      // scroll — so it swallowed every gesture while the outer one silently
      // held all 940px of overflow. Table scrolling looked broken.
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_wideTable));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_horizontalScrollables, findsOneWidget);

      final position = tester.state<ScrollableState>(_horizontalScrollables).position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'the one horizontal scroller must hold the overflow',
      );
    });

    testWidgets('actually scrolls when dragged', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_wideTable));
      await tester.pump(const Duration(milliseconds: 400));

      final position = tester.state<ScrollableState>(_horizontalScrollables).position;
      expect(position.pixels, 0);

      await tester.drag(_horizontalScrollables, const Offset(-180, 0));
      await tester.pump();

      expect(
        position.pixels,
        greaterThan(0),
        reason: 'dragging the table sideways must move it',
      );
    });

    testWidgets('does not make the page scroll sideways', (tester) async {
      // The overflow belongs to the table, not the transcript.
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_wideTable));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });

  group('block splitting', () {
    testWidgets('keeps prose either side of a table', (tester) async {
      await tester.pumpWidget(_host(_wideTable));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('what you should reorder'), findsOneWidget);
      expect(find.textContaining('Order the second one first'), findsOneWidget);
    });

    testWidgets('renders plain prose with no table machinery', (tester) async {
      await tester.pumpWidget(_host('Just a sentence, no table here.'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_horizontalScrollables, findsNothing);
      expect(find.textContaining('Just a sentence'), findsOneWidget);
    });

    testWidgets('handles a table with nothing around it', (tester) async {
      await tester.pumpWidget(_host(
        '| A | B |\n| :--- | ---: |\n| one | 2 |\n',
      ));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('one'), findsOneWidget);
    });

    testWidgets('survives a half-streamed table', (tester) async {
      // Deltas arrive mid-row, so the parser sees a separator with no body yet.
      await tester.pumpWidget(_host('| Product | Stock |\n| :--- | ---'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits 360dp in ${brightness.name} mode', (tester) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(_wideTable, brightness: brightness));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
