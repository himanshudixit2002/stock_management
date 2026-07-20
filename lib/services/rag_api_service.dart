import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session_model.dart';

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
  static String get _baseUrl {
    if (kDebugMode) {
      // Local development
      if (!kIsWeb && Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }
      return 'http://localhost:8000';
    }
    // Production Cloud Run URL
    return 'https://rag-backend-647731796550.asia-south1.run.app';
  }

  /// Sends a question to the RAG backend and returns a parsed [RagResponse].
  ///
  /// Supports the new structured JSON response format with fallback parsing
  /// for legacy `[ACTION: {...}]` blocks in the answer text.
  /// Retries up to 3 times with exponential backoff on network errors.
  static Future<RagResponse> askQuestion(
    String question, {
    String? context,
    List<Map<String, String>>? chatHistory,
  }) async {
    final url = Uri.parse('$_baseUrl/api/chat');
    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
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
            .timeout(const Duration(seconds: 30));

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
                debugPrint('Failed to parse legacy action JSON: $e');
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
            text: 'Error: Server returned status ${response.statusCode}',
          );
        }
      } on SocketException catch (_) {
        if (attempt < maxRetries) {
          // Exponential backoff: 1s, 2s, 4s
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        return RagResponse(
          text:
              'Connection error: Could not reach the backend after ${maxRetries + 1} attempts.',
        );
      } on TimeoutException catch (_) {
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        return RagResponse(
          text: 'Request timed out after ${maxRetries + 1} attempts.',
        );
      } catch (e) {
        return RagResponse(
          text: 'Connection error: Could not reach the backend ($e).',
        );
      }
    }

    // Should never reach here, but just in case
    return RagResponse(text: 'Unexpected error occurred.');
  }

  /// Streams the response from the RAG backend using Server-Sent Events (SSE).
  ///
  /// Each yielded string is a text chunk. The stream ends when the server
  /// sends `[DONE]` or the connection closes.
  static Stream<String> askQuestionStream(
    String question, {
    String? context,
    List<Map<String, String>>? chatHistory,
  }) async* {
    final url = Uri.parse('$_baseUrl/api/chat/stream');

    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      request.body = jsonEncode({
        'question': question,
        if (context != null) 'context': context,
        if (chatHistory != null && chatHistory.isNotEmpty)
          'chat_history': chatHistory,
      });

      final client = http.Client();
      try {
        final streamedResponse = await client
            .send(request)
            .timeout(const Duration(seconds: 30));

        if (streamedResponse.statusCode != 200) {
          yield 'Error: Server returned status ${streamedResponse.statusCode}';
          return;
        }

        // Buffer for incomplete lines across chunks
        String buffer = '';

        await for (final chunk
            in streamedResponse.stream.transform(utf8.decoder)) {
          buffer += chunk;

          // Process complete lines
          while (buffer.contains('\n')) {
            final newlineIndex = buffer.indexOf('\n');
            final line = buffer.substring(0, newlineIndex).trim();
            buffer = buffer.substring(newlineIndex + 1);

            if (line.isEmpty) continue;

            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();

              // Check for end-of-stream signal
              if (data == '[DONE]') return;

              // Try parsing as JSON first (some SSE backends wrap in JSON)
              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                if (json.containsKey('text')) {
                  yield json['text'] as String;
                } else if (json.containsKey('content')) {
                  yield json['content'] as String;
                } else {
                  yield data;
                }
              } catch (_) {
                // Not JSON, yield as plain text
                if (data.isNotEmpty) {
                  yield data;
                }
              }
            }
          }
        }

        // Process any remaining buffer
        if (buffer.trim().isNotEmpty) {
          final line = buffer.trim();
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data != '[DONE]' && data.isNotEmpty) {
              yield data;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      yield 'Streaming error: $e';
    }
  }
}
