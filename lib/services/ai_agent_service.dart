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

  /// Sends spoken natural language command for hands-free stock mutations.
  static Future<Map<String, dynamic>?> processVoiceCommand(String speechText) async {
    final url = Uri.parse('$_baseUrl/api/agent/voice_command');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'speech_text': speechText}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error processing voice command: $e");
    }
    return null;
  }

  /// Triggers full 24/7 background autopilot sweep across all sub-agents.
  static Future<Map<String, dynamic>?> triggerSwarmAutopilot() async {
    final url = Uri.parse('$_baseUrl/api/swarm/autopilot');
    try {
      final response = await http.post(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error triggering swarm autopilot: $e");
    }
    return null;
  }

  /// 1-Click Human Approval for queued high-value Purchase Orders.
  static Future<Map<String, dynamic>?> approvePendingPo(String poId) async {
    final url = Uri.parse('$_baseUrl/api/swarm/approve_po');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'po_id': poId}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error approving PO $poId: $e");
    }
    return null;
  }

  /// Fetches statistical safety stock and ABC classification breakdowns.
  static Future<Map<String, dynamic>?> fetchSafetyStock() async {
    final url = Uri.parse('$_baseUrl/api/agent/safety_stock');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error fetching safety stock: $e");
    }
    return null;
  }

  /// Syncs user's actual live inventory from client SQLite/Firestore to AI engine.
  static Future<bool> syncUserInventory(List<Map<String, dynamic>> products) async {
    if (products.isEmpty) return false;
    final url = Uri.parse('$_baseUrl/api/inventory/sync');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'products': products}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error syncing user inventory to AI engine: $e");
    }
    return false;
  }
}


