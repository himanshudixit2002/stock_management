import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/screens/ai/ai_chat_screen.dart';
import 'package:stock_management/screens/ai/widgets/chat_composer.dart';
import 'package:stock_management/screens/ai/widgets/chat_empty_state.dart';
import 'package:stock_management/screens/ai/widgets/chat_status.dart';
import 'package:stock_management/services/rag_api_service.dart';

/// The screen takes its backend by injection precisely so this file can exist —
/// `RagApiService` is a set of statics over `http`, and the inventory providers
/// build Firestore in their field initialisers.
Widget _host({
  AskStream? askStream,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: AiChatScreen(
        askStream: askStream,
        contextBuilder: (_) async => 'INVENTORY STATS: Total Products: 3',
      ),
    );

/// Emits [events] with a real gap between them, so a test can observe the
/// transcript mid-stream.
AskStream _streamOf(List<Map<String, dynamic>> events) {
  return (question, {String context = '', List<Map<String, String>> history = const []}) async* {
    for (final e in events) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      yield e;
    }
  };
}

Map<String, dynamic> _done(String answer) => {
      'type': 'done',
      'response': RagResponse(answer, null, responseKind: 'prose'),
    };

/// Repeated `pump()` rather than `pumpAndSettle()`: the entrance animations and
/// the streaming cursor leave periodic timers that `pumpAndSettle` never
/// considers finished.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Sends [question] and advances far enough for the injected stream to drain.
///
/// Each step is small so a test can stop part-way and observe a half-streamed
/// answer; [steps] controls how far it runs.
Future<void> _ask(
  WidgetTester tester,
  String question, {
  int steps = 8,
}) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 12));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the empty state', () {
    testWidgets('offers suggestions instead of a seeded greeting table', (
      tester,
    ) async {
      // The old screen seeded the message list with a markdown *table* of
      // commands, so the first thing a new user saw was a scrollable table.
      await tester.pumpWidget(_host());
      await _settle(tester);

      expect(find.byType(ChatEmptyState), findsOneWidget);
      expect(find.text('Ask about your inventory'), findsOneWidget);
      expect(find.text(chatSuggestions.first.title), findsOneWidget);
    });

    testWidgets('disappears once there is a conversation', (tester) async {
      // Suggestions used to be a chip strip pinned above the composer forever.
      await tester.pumpWidget(_host(askStream: _streamOf([_done('Hi.')])));
      await _settle(tester);

      await tester.tap(find.text(chatSuggestions.first.title));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 12));
      }

      expect(find.byType(ChatEmptyState), findsNothing);
      expect(find.text(chatSuggestions.first.prompt), findsOneWidget);
    });
  });

  group('streaming', () {
    testWidgets('renders deltas as they arrive, then the final answer', (
      tester,
    ) async {
      await tester.pumpWidget(_host(
        askStream: _streamOf([
          {'type': 'delta', 'content': 'You should '},
          {'type': 'delta', 'content': 'reorder 3 items.'},
          _done('You should reorder 3 items.'),
        ]),
      ));
      await _settle(tester);

      // Part-way: the first delta is on screen before the answer is finished.
      await _ask(tester, 'what do I reorder?', steps: 4);
      expect(find.textContaining('You should'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.textContaining('reorder 3 items.'), findsOneWidget);
    });

    testWidgets('shows the real status frames, not invented reasoning', (
      tester,
    ) async {
      // The old indicator displayed canned lines like "Initializing semantic
      // query embedding" chosen by keyword-matching the question, while these
      // genuine frames were discarded.
      // Held open rather than completed, so the indicator is still on screen
      // when the assertion runs.
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_host(
        askStream: (q, {String context = '', List<Map<String, String>> history = const []}) =>
            controller.stream,
      ));
      await _settle(tester);

      await _ask(tester, 'stock?', steps: 2);
      controller.add({'type': 'status', 'message': 'Reading live inventory…'});
      await tester.pump();
      await tester.pump();

      expect(find.byType(ChatStatusIndicator), findsOneWidget);
      expect(find.text('Reading live inventory…'), findsOneWidget);

      // A second frame marks the first as finished and shows the new one. Both
      // strings came from the backend — the indicator never writes its own.
      controller.add({'type': 'status', 'message': 'Crunching the numbers…'});
      await tester.pump();
      await tester.pump();

      expect(find.text('Reading live inventory…'), findsOneWidget);
      expect(find.text('Crunching the numbers…'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('a reset discards partial text so it cannot double up', (
      tester,
    ) async {
      // The server emits this when it falls back from streaming to a plain POST.
      await tester.pumpWidget(_host(
        askStream: _streamOf([
          {'type': 'delta', 'content': 'Half an answ'},
          {'type': 'reset'},
          _done('The whole answer.'),
        ]),
      ));
      await _settle(tester);

      await _ask(tester, 'q');
      await tester.pump();

      expect(find.textContaining('Half an answ'), findsNothing);
      expect(find.text('The whole answer.'), findsOneWidget);
    });
  });

  group('the status indicator', () {
    testWidgets('falls back to a neutral line when no frames arrive', (
      tester,
    ) async {
      // Deterministic and cached answers never pass through a model, so they
      // stream no status at all. The old widget invented plausible steps here.
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_host(
        askStream: (q, {String context = '', List<Map<String, String>> history = const []}) =>
            controller.stream,
      ));
      await _settle(tester);

      await _ask(tester, 'summary', steps: 2);

      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('does not repeat a re-announced step', (tester) async {
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_host(
        askStream: (q, {String context = '', List<Map<String, String>> history = const []}) =>
            controller.stream,
      ));
      await _settle(tester);

      await _ask(tester, 'q', steps: 2);
      controller.add({'type': 'status', 'message': 'Reading live inventory…'});
      await tester.pump();
      controller.add({'type': 'status', 'message': 'Reading live inventory…'});
      await tester.pump();
      await tester.pump();

      expect(find.text('Reading live inventory…'), findsOneWidget);
    });
  });

  group('failure', () {
    testWidgets('surfaces an error with Retry, not an assistant sentence', (
      tester,
    ) async {
      // Previously a network failure was appended as ordinary assistant prose:
      // indistinguishable from a real answer and impossible to retry.
      await tester.pumpWidget(_host(
        askStream: (q, {String context = '', List<Map<String, String>> history = const []}) =>
            Stream<Map<String, dynamic>>.error(Exception('offline')),
      ));
      await _settle(tester);

      await _ask(tester, 'anything');
      await tester.pump();

      expect(find.textContaining("Couldn't reach the assistant"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('the composer', () {
    testWidgets('will not send an empty question', (tester) async {
      await tester.pumpWidget(_host());
      await _settle(tester);

      final send = tester.widget<InkWell>(
        find.descendant(
          of: find.byTooltip('Send'),
          matching: find.byType(InkWell),
        ),
      );
      expect(send.onTap, isNull);
    });

    testWidgets('offers Stop while an answer is generating', (tester) async {
      // The send button used to keep its full gradient with a null callback, so
      // it looked tappable and there was no way to stop at all.
      final controller = StreamController<Map<String, dynamic>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_host(
        askStream: (q, {String context = '', List<Map<String, String>> history = const []}) =>
            controller.stream,
      ));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'long question');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('Stop generating'), findsOneWidget);
      expect(find.byTooltip('Send'), findsNothing);

      await tester.tap(find.byTooltip('Stop generating'));
      await _settle(tester);

      expect(find.byTooltip('Send'), findsOneWidget);
    });

    testWidgets('is multiline, so a long question does not scroll sideways', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await _settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, greaterThan(1));
      expect(field.minLines, 1);
      expect(field.keyboardType, TextInputType.multiline);
    });
  });

  group('message actions', () {
    testWidgets('copies a single answer to the clipboard', (tester) async {
      // There was no per-message copy before — only a whole-transcript dump.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(_host(askStream: _streamOf([_done('42 units.')])));
      await _settle(tester);

      await _ask(tester, 'how many?');
      await tester.pump();

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(copied, '42 units.');

      // The button flips to a checkmark and resets itself after two seconds;
      // let that timer run or the binding reports it still pending.
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('layout', () {
    for (final brightness in Brightness.values) {
      testWidgets('fits a 360dp phone in ${brightness.name} mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(
          brightness: brightness,
          askStream: _streamOf([
            _done(
              '| Product | Stock | Reorder |\n'
              '| :--- | ---: | ---: |\n'
              '| A product with a long name | 12 | 40 |\n',
            ),
          ]),
        ));
        await _settle(tester);

        await _ask(tester, 'table please');
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
