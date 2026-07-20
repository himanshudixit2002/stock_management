import 'package:flutter/material.dart';
import '../models/chat_session_model.dart';
import '../services/rag_api_service.dart';

/// A contextual suggestion displayed as a chip below the chat.
class SmartSuggestion {
  final String label;
  final IconData icon;
  final String prompt;

  const SmartSuggestion({
    required this.label,
    required this.icon,
    required this.prompt,
  });
}

/// Manages chat sessions, messages, and request lifecycle.
///
/// Key improvements:
/// - Tracks an active request and can cancel it when a new one arrives.
/// - No more streaming state — uses simple loading + response model.
/// - Sessions are in-memory only (cost-effective).
class ChatProvider extends ChangeNotifier {
  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  bool _isLoading = false;
  int _activeRequestId = 0; // Monotonically increasing ID to track active request

  // ── Getters ──────────────────────────────────────────────────────────────

  List<ChatSession> get sessions => _sessions;
  ChatSession? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  List<ChatMessage> get messages => _currentSession?.messages ?? [];

  // ── Constructor ──────────────────────────────────────────────────────────

  ChatProvider() {
    startNewSession();
  }

  // ── Session Management ───────────────────────────────────────────────────

  void startNewSession() {
    cancelActiveRequest();
    final session = ChatSession();
    _sessions.insert(0, session);
    _currentSession = session;
    notifyListeners();
  }

  void switchSession(String sessionId) {
    cancelActiveRequest();
    _currentSession = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => _sessions.first,
    );
    notifyListeners();
  }

  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isEmpty) {
        startNewSession();
        return;
      } else {
        _currentSession = _sessions.first;
      }
    }
    notifyListeners();
  }

  // ── Request Lifecycle ────────────────────────────────────────────────────

  /// Cancels any in-flight AI request.
  void cancelActiveRequest() {
    _activeRequestId++;
    RagApiService.cancelActiveRequest();
    if (_isLoading) {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Message Management ───────────────────────────────────────────────────

  void addUserMessage(String text) {
    if (_currentSession == null) startNewSession();
    final message = ChatMessage(text: text, isUser: true);
    _currentSession!.messages.add(message);
    _currentSession!.messageCount++;
    _currentSession!.lastMessageAt = DateTime.now();

    final userMessages =
        _currentSession!.messages.where((m) => m.isUser).toList();
    if (userMessages.length == 1) {
      _currentSession!.title =
          text.length > 30 ? '${text.substring(0, 30)}...' : text;
    }
    notifyListeners();
  }

  void addBotMessage(ChatMessage message) {
    if (_currentSession == null) return;
    _currentSession!.messages.add(message);
    _currentSession!.messageCount++;
    _currentSession!.lastMessageAt = DateTime.now();
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Returns a unique request ID. If the ID changes before the response
  /// arrives, the response should be discarded (request was superseded).
  int getRequestId() => _activeRequestId;

  /// Check if a request ID is still the active one.
  bool isRequestActive(int requestId) => requestId == _activeRequestId;

  // ── Chat History ─────────────────────────────────────────────────────────

  List<Map<String, String>> getChatHistory() {
    if (_currentSession == null) return [];
    final msgs = _currentSession!.messages;
    final recent = msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs;
    return recent
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  // ── Smart Suggestions ────────────────────────────────────────────────────

  List<SmartSuggestion> getSmartSuggestions() {
    if (_currentSession == null || _currentSession!.messages.isEmpty) {
      return _defaultSuggestions;
    }
    final lastBotMessages =
        _currentSession!.messages.where((m) => !m.isUser).toList();
    if (lastBotMessages.isEmpty) return _defaultSuggestions;

    final lastBot = lastBotMessages.last;
    final intent = lastBot.intent?.toUpperCase() ?? '';
    final hasAction = lastBot.actionPayload != null;
    final text = lastBot.text.toLowerCase();

    if (hasAction && lastBot.actionPayload?['type'] == 'update_stock') {
      return const [
        SmartSuggestion(
          label: 'Check Stock',
          icon: Icons.inventory_2_rounded,
          prompt: 'Show me the current stock levels after the update',
        ),
        SmartSuggestion(
          label: 'Create PO',
          icon: Icons.shopping_cart_rounded,
          prompt: 'Create a purchase order for this item',
        ),
        SmartSuggestion(
          label: 'Low Stock',
          icon: Icons.warning_rounded,
          prompt: 'What items are low in stock?',
        ),
      ];
    }

    if (intent.contains('ANALYTICS') ||
        intent.contains('REPORT') ||
        text.contains('report') ||
        text.contains('trend')) {
      return const [
        SmartSuggestion(
          label: 'Top Products',
          icon: Icons.star_rounded,
          prompt: 'Show top selling products',
        ),
        SmartSuggestion(
          label: 'Low Stock',
          icon: Icons.warning_rounded,
          prompt: 'What items are low in stock?',
        ),
        SmartSuggestion(
          label: 'Overview',
          icon: Icons.pie_chart_rounded,
          prompt: 'Give me a summary of my inventory',
        ),
      ];
    }

    if (text.contains('error') ||
        text.contains('sorry') ||
        text.contains("couldn't") ||
        text.contains('timed out')) {
      return const [
        SmartSuggestion(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          prompt: 'Please try that again',
        ),
        SmartSuggestion(
          label: 'Help',
          icon: Icons.help_outline_rounded,
          prompt: 'What can you help me with?',
        ),
      ];
    }

    return _defaultSuggestions;
  }

  static const List<SmartSuggestion> _defaultSuggestions = [
    SmartSuggestion(
      label: 'Overview',
      icon: Icons.pie_chart_rounded,
      prompt: 'Give me a summary of my inventory',
    ),
    SmartSuggestion(
      label: 'Low Stock',
      icon: Icons.warning_rounded,
      prompt: 'What items are low in stock?',
    ),
    SmartSuggestion(
      label: 'Orders',
      icon: Icons.receipt_long_rounded,
      prompt: 'Show me pending orders',
    ),
  ];
}
