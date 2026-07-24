import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:http/http.dart' as http;

class AiAgentService {
  static String get _baseUrl {
    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }
      return 'http://localhost:8000';
    }
    return 'https://rag-backend-647731796550.asia-south1.run.app';
  }

  /// Fetches proactive reorder recommendations calculated via lead-time demand & ROP formulas.
  static Future<List<Map<String, dynamic>>> fetchAutopilotRecommendations() async {
    final url = Uri.parse('$_baseUrl/api/agent/autopilot');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['recommendations'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error fetching Autopilot recommendations: $e");
    }
    return [];
  }

  /// Scans ledger and stock metrics for shrinkages and anomalous stockouts.
  static Future<List<Map<String, dynamic>>> fetchAnomalies() async {
    final url = Uri.parse('$_baseUrl/api/agent/anomalies');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['anomalies'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error fetching inventory anomalies: $e");
    }
    return [];
  }

  /// Retrieves 30-day time-series demand forecasts & stockout day projections.
  static Future<List<Map<String, dynamic>>> fetchDemandForecasts() async {
    final url = Uri.parse('$_baseUrl/api/agent/forecast');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['forecasts'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error fetching demand forecasts: $e");
    }
    return [];
  }

  /// Gets automated cross-location stock transfer recommendations.
  static Future<List<Map<String, dynamic>>> fetchLocationTransferSuggestions() async {
    final url = Uri.parse('$_baseUrl/api/agent/location_balance');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['transfer_suggestions'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error fetching location transfer suggestions: $e");
    }
    return [];
  }

  /// Submits visual camera detection counts to compare with expected stock and record audit.
  static Future<Map<String, dynamic>?> submitVisualAudit(List<Map<String, dynamic>> detectedItems) async {
    final url = Uri.parse('$_baseUrl/api/agent/visual_audit');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'detected_items': detectedItems,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['audit_summary'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error submitting visual audit: $e");
    }
    return null;
  }
}
