import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'database_service.dart';
import 'ai_backend.dart';

class RagResponse {
  final String text;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? statsPayload;
  final List<dynamic>? executedActions;
  final String? intent;

  /// Products the assistant could not tell apart. When this is populated the
  /// answer is a question, and the user picks one instead of the assistant
  /// guessing which SKU they meant.
  final List<Map<String, dynamic>>? clarificationOptions;

  /// How the answer was produced: `deterministic`, `llm`, `cache`, `pending`.
  /// Useful for spotting when the model is being called for something the
  /// backend could have answered for free.
  final String? answeredBy;
  
  final Map<String, dynamic>? pendingAction;
  final String? responseKind;

  const RagResponse(
    this.text,
    this.actionPayload, {
    this.statsPayload,
    this.executedActions,
    this.intent,
    this.clarificationOptions,
    this.answeredBy,
    this.pendingAction,
    this.responseKind,
  });
}

/// Raised when the assistant is asked something before the app knows which
/// workspace it is acting for. Answering anyway is what made the assistant
/// reply with another tenant's demo inventory, so this is deliberately fatal
/// to the request rather than something we paper over.
class WorkspaceNotReadyException implements Exception {
  const WorkspaceNotReadyException();
  @override
  String toString() => 'WorkspaceNotReadyException';
}

class RagApiService {
  /// Identifies this chat session so the backend can hold a pending action
  /// against it. Confirmations then execute exactly what was previewed, rather
  /// than the backend re-parsing its own rendered message.
  ///
  /// The bound must stay well inside 32 bits. `Random().nextInt(1 << 32)` looks
  /// correct and works on the VM, but dart2js evaluates `1 << 32` to 0 because
  /// JavaScript bitwise operators are 32-bit — so on web it threw
  /// "RangeError: max must be in range 0 < max ≤ 2^32, was 0" on the very first
  /// request, which surfaced to users as a connection failure.
  ///
  /// Building it lazily and defensively matters as much as the bound: this is a
  /// cosmetic session tag, and it must never be the reason a question fails.
  static String? _cachedSessionId;

  static String get _sessionId {
    var id = _cachedSessionId;
    if (id != null) return id;
    try {
      id = 'sess_${DateTime.now().millisecondsSinceEpoch}'
          '_${Random().nextInt(0x3FFFFFFF)}';
    } catch (e) {
      debugPrint('Ask AI: session id generation failed ($e); using a timestamp');
      id = 'sess_${DateTime.now().microsecondsSinceEpoch}';
    }
    _cachedSessionId = id;
    return id;
  }

  /// Whether a company id is known yet. The chat screen checks this before
  /// sending so the user gets a "still loading" state instead of an error.
  static bool get isWorkspaceReady => DatabaseService().companyId.isNotEmpty;

  static const RagResponse _notReady = RagResponse(
    "I'm still loading your workspace. Give it a second and try again.",
    null,
  );

  static Map<String, dynamic> _body(
    String question,
    String? context,
    List<Map<String, String>>? history,
  ) {
    return {
      'question': question,
      'session_id': _sessionId,
      'context': ?context,
      'history': ?history,
    };
  }

  static final RegExp _actionTag =
      RegExp(r'\[ACTION:\s*({.*?})\s*\]', dotAll: true);
  static final RegExp _statsTag =
      RegExp(r'\[STATS:\s*({.*?})\s*\]', dotAll: true);

  /// Pulls the machine-readable trailers out of an answer and returns the
  /// prose the user should actually see.
  static RagResponse _parse(Map<String, dynamic> data) {
    String answer = data['answer'] as String? ?? '';
    final intent = data['intent'] as String?;
    final executedActions = data['executed_actions'] as List<dynamic>?;

    Map<String, dynamic>? actionPayload;
    final actionMatch = _actionTag.firstMatch(answer);
    if (actionMatch != null) {
      try {
        actionPayload = jsonDecode(actionMatch.group(1)!) as Map<String, dynamic>;
        answer = answer.replaceFirst(actionMatch.group(0)!, '').trim();
      } catch (e) {
        debugPrint('Ask AI: could not parse action payload: $e');
      }
    }

    Map<String, dynamic>? statsPayload;
    final statsMatch = _statsTag.firstMatch(answer);
    if (statsMatch != null) {
      try {
        statsPayload = jsonDecode(statsMatch.group(1)!) as Map<String, dynamic>;
        answer = answer.replaceFirst(statsMatch.group(0)!, '').trim();
      } catch (e) {
        debugPrint('Ask AI: could not parse stats payload: $e');
      }
    }

    // The backend executes actions itself, so synthesise the card the UI shows.
    if (actionPayload == null &&
        executedActions != null &&
        executedActions.isNotEmpty) {
      final first = executedActions.first;
      if (first is Map) {
        final tool = first['tool'];
        final result = first['result'];
        if (result is Map && result['success'] == true) {
          const stockTools = {'update_stock', 'audit_inventory'};
          const poTools = {'create_purchase_order'};
          if (stockTools.contains(tool) || poTools.contains(tool)) {
            actionPayload = {
              'type': poTools.contains(tool) ? 'create_po' : 'update_stock',
              'barcode': result['barcode'] ?? '',
              'product_name': result['product_name'] ?? '',
              'qty_change': result['qty_change'] ??
                  result['reorder_qty'] ??
                  result['discrepancy'] ??
                  0,
              'is_executed': true,
            };
          }
        }
      }
    }

    final rawOptions = data['clarification_options'] as List<dynamic>?;

    return RagResponse(
      answer,
      actionPayload,
      statsPayload: statsPayload,
      executedActions: executedActions,
      intent: intent,
      clarificationOptions: rawOptions
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      answeredBy: data['answered_by'] as String?,
      pendingAction: data['pending_action'] as Map<String, dynamic>?,
      responseKind: data['response_kind'] as String?,
    );
  }

  /// Non-streaming ask, with one retry for cold starts.
  static Future<RagResponse> askQuestion(
    String question, {
    String? context,
    List<Map<String, String>>? history,
  }) async {
    if (!isWorkspaceReady) return _notReady;
    final url = Uri.parse('${AiBackend.baseUrl}/api/chat');

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          url,
          headers: await AiBackend.headers(),
          body: jsonEncode(_body(question, context, history)),
        );
        if (response.statusCode == 200) {
          return _parse(jsonDecode(response.body) as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('Ask AI attempt ${attempt + 1} failed: $e');
      }
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    return const RagResponse(
      "I couldn't reach the assistant. Please try again.",
      null,
    );
  }

  /// Asks the assistant, streaming the answer when the transport allows it.
  ///
  /// Events are `{'type': 'status'|'delta'|'reset'|'done', ...}`. The `done`
  /// event carries a fully parsed [RagResponse] under `response`.
  ///
  /// Streaming is treated as an optimisation, never a requirement. Server-sent
  /// events are the most fragile thing this app does over the network — proxies
  /// buffer them, browser HTTP clients differ, and a dropped connection mid-body
  /// is normal. So if the stream fails, or ends without ever delivering a final
  /// answer, this transparently falls back to the plain `/api/chat` request that
  /// the app used before streaming existed. A transport problem degrades the
  /// experience; it must never cost the user their answer.
  static Stream<Map<String, dynamic>> askQuestionStream(
    String question, {
    String? context,
    List<Map<String, String>>? history,
  }) async* {
    if (!isWorkspaceReady) {
      yield {'type': 'done', 'response': _notReady};
      return;
    }

    var delivered = false;
    var sawPartialText = false;
    Object? streamError;

    try {
      await for (final event in _streamEvents(question, context, history)) {
        if (event['type'] == 'delta') sawPartialText = true;
        if (event['type'] == 'done') delivered = true;
        yield event;
      }
    } catch (e) {
      streamError = e;
      debugPrint('Ask AI: streaming transport failed: $e');
    }

    if (delivered) return;

    // Either the stream threw, or it closed without a final answer. Retry once
    // over plain HTTP.
    debugPrint(
      'Ask AI: falling back to non-streaming request'
      '${streamError != null ? ' after $streamError' : ' (stream ended early)'}',
    );

    // Any half-streamed text is about to be superseded; tell the UI to clear it
    // so partial and final content cannot appear concatenated.
    if (sawPartialText) yield {'type': 'reset'};

    final response = await askQuestion(
      question,
      context: context,
      history: history,
    );
    yield {'type': 'done', 'response': response};
  }

  /// The raw SSE read. Throws on transport failure; the caller handles recovery.
  static Stream<Map<String, dynamic>> _streamEvents(
    String question,
    String? context,
    List<Map<String, String>>? history,
  ) async* {
    final url = Uri.parse('${AiBackend.baseUrl}/api/chat/stream');
    final client = http.Client();
    var responseComplete = false;

    try {
      final request = http.Request('POST', url);
      (await AiBackend.headers()).forEach((k, v) => request.headers[k] = v);
      request.body = jsonEncode(_body(question, context, history));

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'stream endpoint returned ${response.statusCode}',
          url,
        );
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty) continue;

        Map<String, dynamic> event;
        try {
          event = jsonDecode(payload) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Ask AI: skipping malformed stream frame: $e');
          continue;
        }

        if (event['type'] == 'done') {
          yield {'type': 'done', 'response': _parse(event)};
        } else {
          yield event;
        }
      }
      responseComplete = true;
    } finally {
      // close() aborts anything still in flight, so only reach for it once the
      // body is done — and never let a close error mask the real one.
      try {
        client.close();
      } catch (e) {
        if (responseComplete) debugPrint('Ask AI: client close: $e');
      }
    }
  }

  /// Pushes the user's live catalog into the assistant's fact layer.
  static Future<bool> syncCatalogToRag(
      List<Map<String, dynamic>> products) async {
    if (products.isEmpty) return false;
    try {
      final response = await http.post(
        Uri.parse('${AiBackend.baseUrl}/api/inventory/sync'),
        headers: await AiBackend.headers(),
        body: jsonEncode({'products': products}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Ask AI: catalog sync failed: $e');
      return false;
    }
  }

  /// Clears cached answers for this company only.
  static Future<void> clearCache() async {
    try {
      await http.post(
        Uri.parse('${AiBackend.baseUrl}/api/cache/clear'),
        headers: await AiBackend.headers(),
      );
    } catch (e) {
      debugPrint('Ask AI: cache clear failed: $e');
    }
  }
}
