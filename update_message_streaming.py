with open('lib/screens/ai/rag_chat_screen.dart', 'r') as f:
    content = f.read()

old_message = """  final String? responseKind;
  bool isActionExecuted;

  _Message(
    this.text,
    this.isUser, {"""

new_message = """  final String? responseKind;
  bool isActionExecuted;
  bool isStreaming;

  _Message(
    this.text,
    this.isUser, {
    this.isStreaming = false,"""

content = content.replace(old_message, new_message)

old_placeholder_update = """            if (placeholderIndex == -1) {
              _messages.add(_Message(buffer.toString(), false));
              placeholderIndex = _messages.length - 1;
              _isLoading = false;
            } else {
              _messages[placeholderIndex] =
                  _Message(buffer.toString(), false);
            }"""

new_placeholder_update = """            if (placeholderIndex == -1) {
              _messages.add(_Message(buffer.toString(), false, isStreaming: true));
              placeholderIndex = _messages.length - 1;
              _isLoading = false;
            } else {
              _messages[placeholderIndex] =
                  _Message(buffer.toString(), false, isStreaming: true);
            }"""

content = content.replace(old_placeholder_update, new_placeholder_update)

with open('lib/screens/ai/rag_chat_screen.dart', 'w') as f:
    f.write(content)
