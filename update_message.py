with open('lib/screens/ai/rag_chat_screen.dart', 'r') as f:
    content = f.read()

old_message = """class _Message {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? statsPayload;
  final List<Map<String, dynamic>>? lowStockItemsPayload;

  /// Products the assistant could not tell apart. Rendered as tappable chips so
  /// the user picks the SKU instead of the assistant guessing.
  final List<Map<String, dynamic>>? clarificationOptions;
  bool isActionExecuted;

  _Message(
    this.text,
    this.isUser, {
    this.actionPayload,
    this.statsPayload,
    this.lowStockItemsPayload,
    this.clarificationOptions,
    this.isActionExecuted = false,
  });
}"""

new_message = """class _Message {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? statsPayload;
  final List<Map<String, dynamic>>? lowStockItemsPayload;

  /// Products the assistant could not tell apart. Rendered as tappable chips so
  /// the user picks the SKU instead of the assistant guessing.
  final List<Map<String, dynamic>>? clarificationOptions;
  final Map<String, dynamic>? pendingAction;
  final String? responseKind;
  bool isActionExecuted;

  _Message(
    this.text,
    this.isUser, {
    this.actionPayload,
    this.statsPayload,
    this.lowStockItemsPayload,
    this.clarificationOptions,
    this.pendingAction,
    this.responseKind,
    this.isActionExecuted = false,
  });
}"""

content = content.replace(old_message, new_message)

with open('lib/screens/ai/rag_chat_screen.dart', 'w') as f:
    f.write(content)
