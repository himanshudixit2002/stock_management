import 'package:uuid/uuid.dart';

/// Represents a single message in a chat conversation.
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Map<String, dynamic>? actionPayload;
  bool isActionExecuted;
  final String? intent;
  final int? latencyMs;
  final bool? cached;

  ChatMessage({
    String? id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.actionPayload,
    this.isActionExecuted = false,
    this.intent,
    this.latencyMs,
    this.cached,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    Map<String, dynamic>? actionPayload,
    bool? isActionExecuted,
    String? intent,
    int? latencyMs,
    bool? cached,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      actionPayload: actionPayload ?? this.actionPayload,
      isActionExecuted: isActionExecuted ?? this.isActionExecuted,
      intent: intent ?? this.intent,
      latencyMs: latencyMs ?? this.latencyMs,
      cached: cached ?? this.cached,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'actionPayload': actionPayload,
      'isActionExecuted': isActionExecuted,
      'intent': intent,
      'latencyMs': latencyMs,
      'cached': cached,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String?,
      text: (map['text'] as String?) ?? '',
      isUser: (map['isUser'] as bool?) ?? false,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : null,
      actionPayload: map['actionPayload'] as Map<String, dynamic>?,
      isActionExecuted: (map['isActionExecuted'] as bool?) ?? false,
      intent: map['intent'] as String?,
      latencyMs: map['latencyMs'] as int?,
      cached: map['cached'] as bool?,
    );
  }
}

/// Represents a chat session containing a list of messages.
class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime lastMessageAt;
  int messageCount;
  final List<ChatMessage> messages;

  ChatSession({
    String? id,
    this.title = 'New Chat',
    DateTime? createdAt,
    DateTime? lastMessageAt,
    this.messageCount = 0,
    List<ChatMessage>? messages,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastMessageAt = lastMessageAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastMessageAt': lastMessageAt.millisecondsSinceEpoch,
      'messageCount': messageCount,
      'messages': messages.map((m) => m.toMap()).toList(),
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'] as String?,
      title: (map['title'] as String?) ?? 'New Chat',
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
      lastMessageAt: map['lastMessageAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageAt'] as int)
          : null,
      messageCount: (map['messageCount'] as int?) ?? 0,
      messages: map['messages'] != null
          ? (map['messages'] as List)
              .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
