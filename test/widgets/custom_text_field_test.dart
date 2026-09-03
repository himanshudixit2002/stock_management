import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/custom_text_field.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

void main() {
  group('CustomTextField focus ownership', () {
    // The widget used to create its FocusNode privately with no way to pass one
    // in, which made next-field traversal structurally impossible across all 19
    // call sites — including login, where the keyboard had to be dismissed
    // before Sign In could be tapped.
    testWidgets('honours an externally supplied focus node', (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        _host(
          CustomTextField(
            controller: controller,
            label: 'Email',
            focusNode: focus,
          ),
        ),
      );

      expect(focus.hasFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('does not dispose a node it did not create', (tester) async {
      // Disposing a caller-owned node would throw the moment the parent used it
      // again — the trap in taking an optional node.
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          CustomTextField(
            controller: controller,
            label: 'Email',
            focusNode: focus,
          ),
        ),
      );
      await tester.pumpWidget(_host(const SizedBox()));

      // Still usable after the field is gone.
      expect(() => focus.hasListeners, returnsNormally);
      focus.dispose();
    });

    testWidgets('still manages its own node when none is given', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(CustomTextField(controller: controller, label: 'Email')),
      );
      await tester.tap(find.byType(TextFormField));
      await tester.pump();

      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)),
        isNotNull,
      );
      // Unmounting must not throw — the internally owned node is disposed here.
      await tester.pumpWidget(_host(const SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });

  group('CustomTextField keyboard action', () {
    testWidgets('fires onSubmitted when the action key is pressed', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var submitted = 0;

      await tester.pumpWidget(
        _host(
          CustomTextField(
            controller: controller,
            label: 'Password',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submitted++,
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitted, 1);
    });

    testWidgets('passes the action through to the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          CustomTextField(
            controller: controller,
            label: 'Email',
            textInputAction: TextInputAction.next,
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.next);
    });

    testWidgets('moves focus to the next field, chaining a form', (
      tester,
    ) async {
      final a = TextEditingController();
      final b = TextEditingController();
      final second = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(
        _host(
          Column(
            children: [
              CustomTextField(
                controller: a,
                label: 'First',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => second.requestFocus(),
              ),
              CustomTextField(
                controller: b,
                label: 'Second',
                focusNode: second,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      expect(second.hasFocus, isFalse);

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      expect(second.hasFocus, isTrue);
    });
  });
}
