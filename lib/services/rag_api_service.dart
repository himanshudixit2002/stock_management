import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Structured response from the RAG backend.
class RagResponse {
  final String text;
  final String intent;
  final Map<String, dynamic>? actionPayload;
  final int retries;
  final bool cached;
  final int latencyMs;

  RagResponse({
    required this.text,
    this.intent = 'GENERAL',
    this.actionPayload,
    this.retries = 0,
    this.cached = false,
    this.latencyMs = 0,
  });
}

class RagApiService {
  static http.Client? _activeClient;

  static String get _baseUrl {
    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }
      return 'http://localhost:8000';
    }
    return 'https://stock-rag-backend-647731796550.asia-south1.run.app';
  }

  /// Cancels any in-flight request. Safe to call even if nothing is active.
  static void cancelActiveRequest() {
    _activeClient?.close();
    _activeClient = null;
  }

  /// Sends a question to the RAG backend and returns a parsed [RagResponse].
  ///
  /// - Cancels any previous in-flight request automatically.
  /// - Single attempt with a generous 60s timeout (Cloud Run needs time on cold start).
  /// - No retries — the user can retry manually or send a new query.
  static Future<RagResponse> askQuestion(
    String question, {
    String? context,
    List<Map<String, String>>? chatHistory,
  }) async {
    // Cancel any previous request
    cancelActiveRequest();

    final client = http.Client();
    _activeClient = client;

    final url = Uri.parse('$_baseUrl/api/chat');

    try {
      final response = await client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'question': question,
              if (context != null) 'context': context,
              if (chatHistory != null && chatHistory.isNotEmpty)
                'chat_history': chatHistory,
            }),
          )
          .timeout(const Duration(seconds: 60));

      // If this client was cancelled while waiting, ignore the response
      if (_activeClient != client) {
        return RagResponse(text: '');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        String rawAnswer =
            (data['answer'] as String?) ?? 'Received empty answer from server.';
        final String intent = (data['intent'] as String?) ?? 'GENERAL';
        final int retries = (data['retries'] as int?) ?? 0;
        final bool cached = (data['cached'] as bool?) ?? false;
        final int latencyMs = (data['latency_ms'] as int?) ?? 0;

        // Try structured action from the response first
        Map<String, dynamic>? actionPayload =
            data['action'] as Map<String, dynamic>?;

        // Fallback: parse legacy [ACTION: {...}] block from text
        if (actionPayload == null) {
          final actionRegex =
              RegExp(r'\[ACTION:\s*({.*?})\s*\]', dotAll: true);
          final match = actionRegex.firstMatch(rawAnswer);
          if (match != null) {
            try {
              final jsonStr = match.group(1)!;
              actionPayload =
                  jsonDecode(jsonStr) as Map<String, dynamic>;
              rawAnswer =
                  rawAnswer.replaceFirst(match.group(0)!, '').trim();
            } catch (e) {
              debugPrint('Failed to parse legacy action JSON: \$e');
            }
          }
        }

        return RagResponse(
          text: rawAnswer,
          intent: intent,
          actionPayload: actionPayload,
          retries: retries,
          cached: cached,
          latencyMs: latencyMs,
        );
      } else {
        return RagResponse(
          text: 'Server error (${response.statusCode}). Please try again.',
        );
      }
    } on TimeoutException catch (_) {
      return RagResponse(
        text: 'Request timed out. The server may be starting up — please try again in a moment.',
      );
    } on SocketException catch (_) {
      return RagResponse(
        text: 'Cannot reach the server. Please check your internet connection.',
      );
    } on http.ClientException catch (_) {
      // This fires when we call client.close() to cancel
      return RagResponse(text: '');
    } catch (e) {
      return RagResponse(
        text: 'Connection error: \$e',
      );
    } finally {
      if (_activeClient == client) {
        _activeClient = null;
      }
    }
  }
}
