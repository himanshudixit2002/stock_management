import re

with open('lib/services/rag_api_service.dart', 'r') as f:
    content = f.read()

# Replace RagResponse fields
old_rag_response = """  final List<Map<String, dynamic>>? clarificationOptions;

  /// How the answer was produced: `deterministic`, `llm`, `cache`, `pending`.
  /// Useful for spotting when the model is being called for something the
  /// backend could have answered for free.
  final String? answeredBy;

  const RagResponse(
    this.text,
    this.actionPayload, {
    this.statsPayload,
    this.executedActions,
    this.intent,
    this.clarificationOptions,
    this.answeredBy,
  });
}"""

new_rag_response = """  final List<Map<String, dynamic>>? clarificationOptions;

  /// How the answer was produced: `deterministic`, `llm`, `cache`, `pending`.
  /// Useful for spotting when the model is being called for something the
  /// backend could have answered for free.
  final String? answeredBy;
  
  final Map<String, dynamic>? pendingAction;
  final String? responseKind;

  const RagResponse(
    this.text,
    this.actionPayload, {
    this.statsPayload,
    this.executedActions,
    this.intent,
    this.clarificationOptions,
    this.answeredBy,
    this.pendingAction,
    this.responseKind,
  });
}"""
content = content.replace(old_rag_response, new_rag_response)

# Replace _parse logic
old_parse_end = """    final rawOptions = data['clarification_options'] as List<dynamic>?;

    return RagResponse(
      answer,
      actionPayload,
      statsPayload: statsPayload,
      executedActions: executedActions,
      intent: intent,
      clarificationOptions: rawOptions
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      answeredBy: data['answered_by'] as String?,
    );
  }"""

new_parse_end = """    final rawOptions = data['clarification_options'] as List<dynamic>?;

    return RagResponse(
      answer,
      actionPayload,
      statsPayload: statsPayload,
      executedActions: executedActions,
      intent: intent,
      clarificationOptions: rawOptions
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      answeredBy: data['answered_by'] as String?,
      pendingAction: data['pending_action'] as Map<String, dynamic>?,
      responseKind: data['response_kind'] as String?,
    );
  }"""
content = content.replace(old_parse_end, new_parse_end)

# Also fix the headers
content = re.sub(r"static Map<String, String> _headers\(\) \{[\s\S]*?\}", "", content)
content = content.replace("headers: _headers()", "headers: AiBackend.headers()")

with open('lib/services/rag_api_service.dart', 'w') as f:
    f.write(content)
