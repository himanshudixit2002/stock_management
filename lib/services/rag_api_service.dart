import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:http/http.dart' as http;

class RagResponse {
  final String text;
  final Map<String, dynamic>? actionPayload;

  RagResponse(this.text, this.actionPayload);
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

  /// Sends a question to the RAG backend and returns a parsed RagResponse.
  static Future<RagResponse> askQuestion(
    String question, {
    String? context,
    List<Map<String, String>>? history,
  }) async {
    final url = Uri.parse('$_baseUrl/api/chat');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          if (context != null) 'context': context,
          if (history != null) 'history': history,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String rawAnswer = data['answer'] ?? 'Received empty answer from server.';
        
        // Parse the action block if it exists
        Map<String, dynamic>? actionPayload;
        final actionRegex = RegExp(r'\[ACTION:\s*({.*?})\s*\]', dotAll: true);
        final match = actionRegex.firstMatch(rawAnswer);
        
        if (match != null) {
          try {
            final jsonStr = match.group(1)!;
            actionPayload = jsonDecode(jsonStr);
            // Remove the action block from the visible text
            rawAnswer = rawAnswer.replaceFirst(match.group(0)!, '').trim();
          } catch (e) {
            print("Failed to parse action JSON: $e");
          }
        }
        
        return RagResponse(rawAnswer, actionPayload);
      } else {
        return RagResponse('Error: Server returned status ${response.statusCode}', null);
      }
    } catch (e) {
      return RagResponse('Connection error: Could not reach the Cloud Run backend ($e).', null);
    }
  }

  /// Clears the backend query cache.
  static Future<void> clearCache() async {
    final url = Uri.parse('$_baseUrl/api/cache/clear');
    try {
      await http.post(url);
    } catch (e) {
      print("Failed to clear backend cache: $e");
    }
  }
}
