with open('lib/screens/ai/rag_chat_screen.dart', 'r') as f:
    content = f.read()

old_content = """        })
        // Preserve empty lines for paragraph spacing
        .join('\\n');

    Widget bubbleContent = SelectionArea(
      child: _buildAdvancedMarkdownContent(context, cleanMarkdownText),
    );"""

new_content = """        })
        // Preserve empty lines for paragraph spacing
        .join('\\n');

    if (widget.message.isStreaming) {
      cleanMarkdownText += ' ▌';
    }

    Widget bubbleContent = SelectionArea(
      child: _buildAdvancedMarkdownContent(context, cleanMarkdownText),
    );"""

content = content.replace(old_content, new_content)

with open('lib/screens/ai/rag_chat_screen.dart', 'w') as f:
    f.write(content)
