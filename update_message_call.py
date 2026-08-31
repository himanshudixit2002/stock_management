import re

with open('lib/screens/ai/rag_chat_screen.dart', 'r') as f:
    content = f.read()

old_call = """    final message = _Message(
      finalResponse.text,
      false,
      actionPayload: finalResponse.actionPayload,
      statsPayload: finalResponse.statsPayload ?? statsMap,
      lowStockItemsPayload:
          isLowStockQuery && lowItemsPayloadList.isNotEmpty ? lowItemsPayloadList : null,
      clarificationOptions: finalResponse.clarificationOptions,
      isActionExecuted: finalResponse.actionPayload?['is_executed'] ?? false,
    );"""

new_call = """    final message = _Message(
      finalResponse.text,
      false,
      actionPayload: finalResponse.actionPayload,
      statsPayload: finalResponse.statsPayload ?? statsMap,
      lowStockItemsPayload:
          isLowStockQuery && lowItemsPayloadList.isNotEmpty ? lowItemsPayloadList : null,
      clarificationOptions: finalResponse.clarificationOptions,
      pendingAction: finalResponse.pendingAction,
      responseKind: finalResponse.responseKind,
      isActionExecuted: finalResponse.actionPayload?['is_executed'] ?? false,
    );"""

content = content.replace(old_call, new_call)
with open('lib/screens/ai/rag_chat_screen.dart', 'w') as f:
    f.write(content)
