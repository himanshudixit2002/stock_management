import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:http/http.dart' as http;

class RagResponse {
  final String text;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? statsPayload;
  final List<dynamic>? executedActions;
  final String? intent;

  RagResponse(
    this.text, 
    this.actionPayload, {
    this.statsPayload,
    this.executedActions,
    this.intent,
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
          // ignore: use_null_aware_elements
          if (context != null) 'context': context,
          // ignore: use_null_aware_elements
          if (history != null) 'history': history,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String rawAnswer = data['answer'] ?? 'Received empty answer from server.';
        final String? intent = data['intent'];
        final List<dynamic>? executedActions = data['executed_actions'];
        
        // Parse action block
        Map<String, dynamic>? actionPayload;
        final actionRegex = RegExp(r'\[ACTION:\s*({.*?})\s*\]', dotAll: true);
        final match = actionRegex.firstMatch(rawAnswer);
        if (match != null) {
          try {
            actionPayload = jsonDecode(match.group(1)!);
            rawAnswer = rawAnswer.replaceFirst(match.group(0)!, '').trim();
          } catch (e) {
            debugPrint("Failed to parse action JSON: $e");
          }
        }

        // If backend executed an action directly, synthesize actionPayload for UI card
        if (actionPayload == null && executedActions != null && executedActions.isNotEmpty) {
          final firstAction = executedActions.first;
          if (firstAction is Map) {
            final tool = firstAction['tool'];
            final res = firstAction['result'];
            if (res is Map && res['success'] == true) {
              final prod = res['product'] ?? {};
              final oldStock = res['old_stock'];
              final newStock = res['new_stock'];
              final calculatedQty = (newStock is num && oldStock is num) ? (newStock - oldStock).toInt() : null;
              actionPayload = {
                'type': tool == 'CreatePurchaseOrder' ? 'create_po' : 'update_stock',
                'barcode': prod['barcode'] ?? res['barcode'] ?? '',
                'product_name': prod['name'] ?? res['product_name'] ?? '',
                'qty_change': res['qty_change'] ?? calculatedQty ?? res['reorder_qty'] ?? 0,
                'is_executed': true,
              };
            }
          }
        }

        // Parse stats block
        Map<String, dynamic>? statsPayload;
        final statsRegex = RegExp(r'\[STATS:\s*({.*?})\s*\]', dotAll: true);
        final statsMatch = statsRegex.firstMatch(rawAnswer);
        if (statsMatch != null) {
          try {
            statsPayload = jsonDecode(statsMatch.group(1)!);
            rawAnswer = rawAnswer.replaceFirst(statsMatch.group(0)!, '').trim();
          } catch (e) {
            debugPrint("Failed to parse stats JSON: $e");
          }
        }
        
        return RagResponse(
          rawAnswer, 
          actionPayload, 
          statsPayload: statsPayload,
          executedActions: executedActions,
          intent: intent,
        );
      } else {
        return RagResponse('Error: Server returned status ${response.statusCode}', null);
      }
    } catch (e) {
      return RagResponse('Connection error: Could not reach the Cloud Run backend ($e).', null);
    }
  }

  /// Syncs catalog products to the RAG backend vectorstore.
  static Future<bool> syncCatalogToRag(List<Map<String, dynamic>> products) async {
    final url = Uri.parse('$_baseUrl/api/ingest');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'products': products}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Failed to sync catalog to RAG backend: $e");
      return false;
    }
  }

  /// Clears the backend query cache.
  static Future<void> clearCache() async {
    final url = Uri.parse('$_baseUrl/api/cache/clear');
    try {
      await http.post(url);
    } catch (e) {
      debugPrint("Failed to clear backend cache: $e");
    }
  }
}
