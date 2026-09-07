import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/widgets/floating_nav_padding.dart';

/// Pumps [child] on a phone-sized surface with the given bottom system inset
/// (gesture bar / navigation bar).
Future<void> pumpPhone(
  WidgetTester tester,
  Widget child, {
  double bottomInset = 0,
  double keyboardInset = 0,
  Size size = const Size(375, 812),
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        viewPadding: EdgeInsets.only(bottom: bottomInset),
        padding: EdgeInsets.only(bottom: bottomInset),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
}

void main() {
  // The pill sits `viewPadding.bottom + kFloatingNavBarBottomGap` up from the
  // bottom edge and is kFloatingNavBarHeight tall. Content must reserve at
  // least that much or it scrolls underneath — the bug this locks down.
  double pillOccupiedHeight(double bottomInset) =>
      bottomInset + kFloatingNavBarBottomGap + kFloatingNavBarHeight;

  group('floating nav geometry', () {
    for (final inset in <double>[0, 34, 48]) {
      testWidgets('content inset clears the pill (bottom inset $inset)',
          (tester) async {
        late double contentInset;
        late double topOffset;
        await pumpPhone(
          tester,
          Builder(
            builder: (context) {
              contentInset = floatingNavContentInset(context);
              topOffset = floatingNavTopOffset(context);
              return const SizedBox();
            },
          ),
          bottomInset: inset,
        );

        expect(
          contentInset,
          greaterThan(pillOccupiedHeight(inset)),
          reason: 'the last content row would sit under the nav pill',
        );
        expect(topOffset, pillOccupiedHeight(inset));
      });
    }

    testWidgets('the Ask-AI button clears the pill on every device inset',
        (tester) async {
      // Mirrors HomeScreen: the button is 56px tall and sits at
      // floatingNavTopOffset + 12 from the bottom edge.
      const askAiHeight = 56.0;
      for (final inset in <double>[0, 34, 48]) {
        late double fabBottom;
        await pumpPhone(
          tester,
          Builder(
            builder: (context) {
              fabBottom = floatingNavTopOffset(context) + 12;
              return const SizedBox();
            },
          ),
          bottomInset: inset,
        );
        expect(
          fabBottom,
          greaterThanOrEqualTo(pillOccupiedHeight(inset)),
          reason: 'Ask-AI button overlaps the nav pill at inset $inset',
        );
        expect(fabBottom + askAiHeight, lessThan(812));
      }
    });

    testWidgets('wide layouts reserve nothing (NavigationRail, no pill)',
        (tester) async {
      late double contentInset;
      late double topOffset;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            contentInset = floatingNavContentInset(context);
            topOffset = floatingNavTopOffset(context);
            return const SizedBox();
          },
        ),
        bottomInset: 34,
        size: const Size(1200, 900),
      );
      expect(contentInset, 0);
      expect(topOffset, 0);
    });

    testWidgets('FloatingNavPadding matches the computed inset',
        (tester) async {
      await pumpPhone(
        tester,
        const Center(child: FloatingNavPadding()),
        bottomInset: 34,
      );
      final box = tester.getSize(find.byType(FloatingNavPadding));
      expect(box.height, greaterThan(34 + 16 + 64));
    });
  });

  group('with the keyboard up', () {
    // The shell's Scaffold resizes its body away from the keyboard, so the
    // pill — positioned at bottom: 0 of that body — was carried up and left
    // hovering on top of the keyboard whenever a field took focus. The tab
    // content also reserved ~112px for a pill that was no longer where it
    // said it was, and viewPadding.bottom collapses to 0 while the keyboard
    // is up, so the reserved amount changed mid-interaction and the list
    // visibly jumped.
    testWidgets('the pill is hidden and reserves no content inset', (
      tester,
    ) async {
      late bool hidden;
      late double contentInset;
      late double topOffset;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            hidden = floatingNavHidden(context);
            contentInset = floatingNavContentInset(context);
            topOffset = floatingNavTopOffset(context);
            return const SizedBox();
          },
        ),
        bottomInset: 34,
        keyboardInset: 336,
      );

      expect(hidden, isTrue);
      expect(contentInset, 0);
      expect(topOffset, 0);
    });

    testWidgets('the pill comes back when the keyboard closes', (tester) async {
      late bool hidden;
      late double contentInset;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            hidden = floatingNavHidden(context);
            contentInset = floatingNavContentInset(context);
            return const SizedBox();
          },
        ),
        bottomInset: 34,
      );

      expect(hidden, isFalse);
      expect(contentInset, greaterThan(0));
    });
  });

  group('a stray bottom inset is not a keyboard', () {
    // The phone layout has no other navigation, so treating any inset > 0 as
    // "keyboard open" risked hiding the pill for good on a mobile browser that
    // reports a small inset for its own chrome.
    testWidgets('a small inset leaves the pill in place', (tester) async {
      late bool hidden;
      late double contentInset;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            hidden = floatingNavHidden(context);
            contentInset = floatingNavContentInset(context);
            return const SizedBox();
          },
        ),
        bottomInset: 34,
        keyboardInset: kKeyboardInsetThreshold - 1,
      );
      expect(hidden, isFalse);
      expect(contentInset, greaterThan(0));
    });

    testWidgets('a keyboard-sized inset still hides it', (tester) async {
      late bool hidden;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            hidden = floatingNavHidden(context);
            return const SizedBox();
          },
        ),
        keyboardInset: kKeyboardInsetThreshold + 1,
      );
      expect(hidden, isTrue);
    });
  });
}
