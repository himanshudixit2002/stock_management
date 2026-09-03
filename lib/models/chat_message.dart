/// How a message ended up on screen.
enum ChatRole { user, assistant }

/// Where an assistant message is in its lifecycle.
///
/// [failed] exists because a network failure used to be rendered as an ordinary
/// assistant sentence — indistinguishable from a real answer, and with no way to
/// retry it.
enum ChatStatus { streaming, complete, failed }

/// One turn in the Ask AI conversation.
///
/// Promoted out of the chat screen, where it was a private class with no
/// timestamp and a hand-written encoder that silently dropped [pendingAction]
/// and [responseKind] — so confirm cards and no-history prompts disappeared
/// whenever the history was reloaded.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.role,
    String? id,
    DateTime? createdAt,
    this.status = ChatStatus.complete,
    this.actionPayload,
    this.statsPayload,
    this.lowStockItemsPayload,
    this.clarificationOptions,
    this.pendingAction,
    this.responseKind,
    this.answeredBy,
    this.isActionExecuted = false,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${role.name}',
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String text;
  final ChatRole role;
  final DateTime createdAt;
  final ChatStatus status;

  /// A stock movement the assistant proposes, rendered as a confirm card.
  final Map<String, dynamic>? actionPayload;

  /// The inventory snapshot behind a stats answer.
  final Map<String, dynamic>? statsPayload;

  final List<Map<String, dynamic>>? lowStockItemsPayload;

  /// Products the assistant could not tell apart, offered as chips so the user
  /// picks the SKU rather than the assistant guessing.
  final List<Map<String, dynamic>>? clarificationOptions;

  /// A write awaiting confirmation.
  final Map<String, dynamic>? pendingAction;

  /// The backend's `response_kind`: preview / clarification / product_detail /
  /// report / no_history / executed / prose.
  final String? responseKind;

  /// The backend's `answered_by`: deterministic / llm / cache / pending /
  /// fallback. Useful for spotting when the model is being paid for something
  /// the backend could answer for free.
  final String? answeredBy;

  final bool isActionExecuted;

  bool get isUser => role == ChatRole.user;
  bool get isStreaming => status == ChatStatus.streaming;
  bool get hasFailed => status == ChatStatus.failed;

  ChatMessage copyWith({
    String? text,
    ChatStatus? status,
    Map<String, dynamic>? actionPayload,
    Map<String, dynamic>? statsPayload,
    List<Map<String, dynamic>>? lowStockItemsPayload,
    List<Map<String, dynamic>>? clarificationOptions,
    Map<String, dynamic>? pendingAction,
    String? responseKind,
    String? answeredBy,
    bool? isActionExecuted,
  }) {
    return ChatMessage(
      id: id,
      createdAt: createdAt,
      role: role,
      text: text ?? this.text,
      status: status ?? this.status,
      actionPayload: actionPayload ?? this.actionPayload,
      statsPayload: statsPayload ?? this.statsPayload,
      lowStockItemsPayload: lowStockItemsPayload ?? this.lowStockItemsPayload,
      clarificationOptions: clarificationOptions ?? this.clarificationOptions,
      pendingAction: pendingAction ?? this.pendingAction,
      responseKind: responseKind ?? this.responseKind,
      answeredBy: answeredBy ?? this.answeredBy,
      isActionExecuted: isActionExecuted ?? this.isActionExecuted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'role': role.name,
        'createdAt': createdAt.toIso8601String(),
        // A half-streamed message is restored as complete: there is no stream
        // left to resume, and restoring it as `streaming` would show a cursor
        // that never stops blinking.
        'status': (status == ChatStatus.streaming ? ChatStatus.complete : status)
            .name,
        'actionPayload': actionPayload,
        'statsPayload': statsPayload,
        'lowStockItemsPayload': lowStockItemsPayload,
        'clarificationOptions': clarificationOptions,
        'pendingAction': pendingAction,
        'responseKind': responseKind,
        'answeredBy': answeredBy,
        'isActionExecuted': isActionExecuted,
      };

  /// Tolerant of every shape this has ever been stored in — including the old
  /// `isUser` boolean and records with no id, timestamp or status.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String?;
    final role = roleName != null
        ? ChatRole.values.firstWhere(
            (r) => r.name == roleName,
            orElse: () => ChatRole.assistant,
          )
        : (json['isUser'] == true ? ChatRole.user : ChatRole.assistant);

    final statusName = json['status'] as String?;
    final status = statusName != null
        ? ChatStatus.values.firstWhere(
            (s) => s.name == statusName,
            orElse: () => ChatStatus.complete,
          )
        : ChatStatus.complete;

    return ChatMessage(
      id: json['id'] as String?,
      text: (json['text'] as String?) ?? '',
      role: role,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? ''),
      status: status,
      actionPayload: _map(json['actionPayload']),
      statsPayload: _map(json['statsPayload']),
      lowStockItemsPayload: _list(json['lowStockItemsPayload']),
      clarificationOptions: _list(json['clarificationOptions']),
      pendingAction: _map(json['pendingAction']),
      responseKind: json['responseKind'] as String?,
      answeredBy: json['answeredBy'] as String?,
      isActionExecuted: json['isActionExecuted'] == true,
    );
  }

  static Map<String, dynamic>? _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>>? _list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : null;
}
