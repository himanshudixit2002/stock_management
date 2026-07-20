import 'package:flutter/material.dart';
import '../models/chat_session_model.dart';

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

/// Manages chat sessions, messages, streaming state, and smart suggestions.
///
/// Sessions are stored in-memory only (not persisted to Firestore) to stay
/// cost-effective. Data persists during the app lifecycle.
class ChatProvider extends ChangeNotifier {
  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  bool _isLoading = false;
  bool _isStreaming = false;
  String _streamingText = '';

  // ── Getters ──────────────────────────────────────────────────────────────

  List<ChatSession> get sessions => _sessions;
  ChatSession? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String get streamingText => _streamingText;
  List<ChatMessage> get messages => _currentSession?.messages ?? [];

  // ── Constructor ──────────────────────────────────────────────────────────

  ChatProvider() {
    startNewSession();
  }

  // ── Session Management ───────────────────────────────────────────────────

  /// Creates a new chat session and sets it as the current one.
  void startNewSession() {
    final session = ChatSession();
    _sessions.insert(0, session);
    _currentSession = session;
    notifyListeners();
  }

  /// Switches the active session to the one matching [sessionId].
  void switchSession(String sessionId) {
    _currentSession = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => _sessions.first,
    );
    notifyListeners();
  }

  /// Removes the session with [sessionId]. If it was the active session,
  /// automatically selects the next available or creates a fresh one.
  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isEmpty) {
        startNewSession();
        return; // startNewSession already notifies
      } else {
        _currentSession = _sessions.first;
      }
    }
    notifyListeners();
  }

  // ── Message Management ───────────────────────────────────────────────────

  /// Adds a user message to the current session.
  void addUserMessage(String text) {
    if (_currentSession == null) startNewSession();
    final message = ChatMessage(text: text, isUser: true);
    _currentSession!.messages.add(message);
    _currentSession!.messageCount++;
    _currentSession!.lastMessageAt = DateTime.now();

    // Auto-title from the first user message
    final userMessages =
        _currentSession!.messages.where((m) => m.isUser).toList();
    if (userMessages.length == 1) {
      _currentSession!.title =
          text.length > 30 ? '${text.substring(0, 30)}...' : text;
    }
    notifyListeners();
  }

  /// Adds a bot response message to the current session.
  void addBotMessage(ChatMessage message) {
    if (_currentSession == null) return;
    _currentSession!.messages.add(message);
    _currentSession!.messageCount++;
    _currentSession!.lastMessageAt = DateTime.now();
    notifyListeners();
  }

  /// Updates the loading state (shown before a response arrives).
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // ── Streaming ────────────────────────────────────────────────────────────

  /// Starts a streaming response session.
  void startStreaming() {
    _isStreaming = true;
    _streamingText = '';
    notifyListeners();
  }

  /// Appends an incoming text chunk to the streaming buffer.
  void appendStreamChunk(String chunk) {
    _streamingText += chunk;
    notifyListeners();
  }

  /// Ends the streaming session and commits the final message.
  void finalizeStream(ChatMessage finalMessage) {
    _isStreaming = false;
    _streamingText = '';
    addBotMessage(finalMessage);
  }

  // ── Chat History ─────────────────────────────────────────────────────────

  /// Returns the last 10 messages formatted for the API's `chat_history`
  /// parameter: `[{role: 'user'|'assistant', content: '...'}, ...]`
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

  /// Returns contextual quick-action suggestions based on the last bot
  /// response. Falls back to sensible defaults for new conversations.
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

    // After a stock update action
    if (hasAction && lastBot.actionPayload?['type'] == 'update_stock') {
      return const [
        SmartSuggestion(
          label: 'Check Updated Stock',
          icon: Icons.inventory_2_rounded,
          prompt: 'Show me the current stock levels after the update',
        ),
        SmartSuggestion(
          label: 'Create PO',
          icon: Icons.shopping_cart_rounded,
          prompt: 'Create a purchase order for this item',
        ),
        SmartSuggestion(
          label: 'Stock History',
          icon: Icons.history_rounded,
          prompt: 'Show stock movement history',
        ),
        SmartSuggestion(
          label: 'Low Stock Items',
          icon: Icons.warning_rounded,
          prompt: 'What items are low in stock?',
        ),
      ];
    }

    // After analytics / report intent
    if (intent.contains('ANALYTICS') ||
        intent.contains('REPORT') ||
        text.contains('report') ||
        text.contains('analytics') ||
        text.contains('trend')) {
      return const [
        SmartSuggestion(
          label: 'Export Report',
          icon: Icons.download_rounded,
          prompt: 'Export this report as a file',
        ),
        SmartSuggestion(
          label: 'Show Chart',
          icon: Icons.bar_chart_rounded,
          prompt: 'Show this data as a chart',
        ),
        SmartSuggestion(
          label: 'Compare Period',
          icon: Icons.compare_arrows_rounded,
          prompt: 'Compare with last month',
        ),
        SmartSuggestion(
          label: 'Top Products',
          icon: Icons.star_rounded,
          prompt: 'Show top selling products',
        ),
      ];
    }

    // After an error response
    if (text.contains('error') ||
        text.contains('sorry') ||
        text.contains("couldn't") ||
        text.contains('failed')) {
      return const [
        SmartSuggestion(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          prompt: 'Please try that again',
        ),
        SmartSuggestion(
          label: 'Rephrase',
          icon: Icons.edit_rounded,
          prompt: 'Let me rephrase my question',
        ),
        SmartSuggestion(
          label: 'Help',
          icon: Icons.help_outline_rounded,
          prompt: 'What can you help me with?',
        ),
        SmartSuggestion(
          label: 'Status',
          icon: Icons.info_outline_rounded,
          prompt: 'Check system status',
        ),
      ];
    }

    return _defaultSuggestions;
  }

  static const List<SmartSuggestion> _defaultSuggestions = [
    SmartSuggestion(
      label: 'Inventory Overview',
      icon: Icons.pie_chart_rounded,
      prompt: 'Give me a summary of my inventory',
    ),
    SmartSuggestion(
      label: 'Low Stock Alert',
      icon: Icons.warning_rounded,
      prompt: 'What items are low in stock?',
    ),
    SmartSuggestion(
      label: 'Pending Orders',
      icon: Icons.receipt_long_rounded,
      prompt: 'Show me pending orders',
    ),
    SmartSuggestion(
      label: 'Sales Trend',
      icon: Icons.trending_up_rounded,
      prompt: 'Show me the sales trend',
    ),
  ];
}
