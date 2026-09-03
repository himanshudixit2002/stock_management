import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'database_service.dart';
import 'ai_backend.dart';

/// A list, or the reason one could not be fetched.
///
/// These calls used to return `[]` for every failure — a non-200, a network
/// error, a malformed body — so the dashboard rendered an empty, healthy-looking
/// "no issues" state when the backend was down or the token was rejected. An
/// error and an all-clear are opposite answers and must not look the same.
class AgentResult {
  const AgentResult.ok(this.items) : error = null;
  const AgentResult.failed(this.error) : items = const [];

  final List<Map<String, dynamic>> items;
  final String? error;

  bool get isError => error != null;
  bool get isEmpty => items.isEmpty;
}

class AiAgentService {
  // Base URL and header construction live in AiBackend so there is exactly one
  // definition of how this app talks to the assistant. They were previously
  // duplicated here with *different* behaviour when the company id was missing
  // — this service dropped the header and let the request through, which is how
  // header-less requests reached the backend and came back with demo data.

  /// Whether a workspace is known yet. These endpoints feed dashboards, so
  /// without one there is nothing meaningful to fetch and callers get an empty
  /// result rather than an exception or another tenant's data.
  static bool get _ready => DatabaseService().companyId.isNotEmpty;

  /// Fetches proactive reorder recommendations calculated via lead-time demand & ROP formulas.
  static Future<AgentResult> fetchAutopilotRecommendations() async {
    if (!_ready) return const AgentResult.ok([]);
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/autopilot');
    try {
      final response = await http.get(url, headers: await AiBackend.headers());
      if (response.statusCode != 200) {
        return AgentResult.failed(
          'The assistant service returned ${response.statusCode}.',
        );
      }
      final data = jsonDecode(response.body);
      final list = data['recommendations'] as List? ?? [];
      // whereType, not cast: cast() is lazy and throws on iteration — outside
      // this try — the moment a row is not a map.
      return AgentResult.ok(list.whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      debugPrint("Error fetching Autopilot recommendations: $e");
      return const AgentResult.failed(
        'Could not reach the assistant service.',
      );
    }
  }

  /// Scans ledger and stock metrics for shrinkages and anomalous stockouts.
  static Future<AgentResult> fetchAnomalies() async {
    if (!_ready) return const AgentResult.ok([]);
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/anomalies');
    try {
      final response = await http.get(url, headers: await AiBackend.headers());
      if (response.statusCode != 200) {
        return AgentResult.failed(
          'The assistant service returned ${response.statusCode}.',
        );
      }
      final data = jsonDecode(response.body);
      final list = data['anomalies'] as List? ?? [];
      // whereType, not cast: cast() is lazy and throws on iteration — outside
      // this try — the moment a row is not a map.
      return AgentResult.ok(list.whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      debugPrint("Error fetching inventory anomalies: $e");
      return const AgentResult.failed(
        'Could not reach the assistant service.',
      );
    }
  }

  /// Retrieves 30-day time-series demand forecasts & stockout day projections.
  static Future<AgentResult> fetchDemandForecasts() async {
    if (!_ready) return const AgentResult.ok([]);
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/forecast');
    try {
      final response = await http.get(url, headers: await AiBackend.headers());
      if (response.statusCode != 200) {
        return AgentResult.failed(
          'The assistant service returned ${response.statusCode}.',
        );
      }
      final data = jsonDecode(response.body);
      final list = data['forecasts'] as List? ?? [];
      return AgentResult.ok(list.whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      debugPrint("Error fetching demand forecasts: $e");
      return const AgentResult.failed(
        'Could not reach the assistant service.',
      );
    }
  }

  /// Gets automated cross-location stock transfer recommendations.
  static Future<AgentResult> fetchLocationTransferSuggestions() async {
    if (!_ready) return const AgentResult.ok([]);
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/location_balance');
    try {
      final response = await http.get(url, headers: await AiBackend.headers());
      if (response.statusCode != 200) {
        return AgentResult.failed(
          'The assistant service returned ${response.statusCode}.',
        );
      }
      final data = jsonDecode(response.body);
      final list = data['transfer_suggestions'] as List? ?? [];
      return AgentResult.ok(list.whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      debugPrint("Error fetching location transfer suggestions: $e");
      return const AgentResult.failed(
        'Could not reach the assistant service.',
      );
    }
  }

  /// Submits visual camera detection counts to compare with expected stock and record audit.
  static Future<Map<String, dynamic>?> submitVisualAudit(List<Map<String, dynamic>> detectedItems) async {
    if (!_ready) return null;
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/visual_audit');
    try {
      final response = await http.post(
        url,
        headers: await AiBackend.headers(),
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
    if (!_ready) return null;
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/voice_command');
    try {
      final response = await http.post(
        url,
        headers: await AiBackend.headers(),
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
    if (!_ready) return null;
    final url = Uri.parse('${AiBackend.baseUrl}/api/swarm/autopilot');
    try {
      final response = await http.post(url, headers: await AiBackend.headers());
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
    if (!_ready) return null;
    final url = Uri.parse('${AiBackend.baseUrl}/api/swarm/approve_po');
    try {
      final response = await http.post(
        url,
        headers: await AiBackend.headers(),
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
    if (!_ready) return null;
    final url = Uri.parse('${AiBackend.baseUrl}/api/agent/safety_stock');
    try {
      final response = await http.get(url, headers: await AiBackend.headers());
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("Error fetching safety stock: $e");
    }
    return null;
  }

  /// Syncs user's actual live inventory from client SQLite/Firestore to AI engine.
  static Future<bool> syncUserInventory(List<Map<String, dynamic>> products, {String? companyId}) async {
    if (products.isEmpty) return false;
    if (!_ready && companyId == null) return false;
    final url = Uri.parse('${AiBackend.baseUrl}/api/inventory/sync');
    try {
      final response = await http.post(
        url,
        headers: await AiBackend.headers(companyId),
        body: jsonEncode({'products': products}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error syncing user inventory to AI engine: $e");
    }
    return false;
  }
}


