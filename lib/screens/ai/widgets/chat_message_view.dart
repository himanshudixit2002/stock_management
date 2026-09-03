import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../models/chat_message.dart';
import '../../../utils/date_formats.dart';
import 'chat_markdown.dart';

/// One turn in the transcript.
///
/// Assistant answers render as a **document** — full content width, no bubble,
/// no avatar — because they are frequently long: multi-column inventory tables,
/// reorder lists, audits. Boxing that inside a 720px bubble with a shimmering
/// avatar made every one of them harder to read. Only the user's own turns are
/// bubbles, which is what keeps the conversation legible as a conversation.
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.onRetry,
    this.trailing,
    this.streamingText,
  });

  final ChatMessage message;

  /// Shown on a failed turn. A failure used to render as an ordinary assistant
  /// sentence, so it was indistinguishable from an answer and could not be
  /// retried.
  final VoidCallback? onRetry;

  /// Cards the screen attaches under an answer — stats, low stock, confirm.
  final Widget? trailing;

  /// Live text while this message is streaming.
  ///
  /// Passed as a notifier so a token repaints only this widget. Previously each
  /// delta called `setState` on the whole screen, re-running the markdown split
  /// for every message on screen.
  final ValueListenable<String>? streamingText;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _user(context) : _assistant(context);
  }

  Widget _user(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: AppTheme.spacingLG,
        bottom: AppTheme.spacingXS,
        // Enough to keep the bubble from spanning the full width, but not the
        // 48px that squeezed a two-line question on a phone.
        left: MediaQuery.sizeOf(context).width < 400 ? 32 : 56,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            // primaryGrad(context), not the const primaryGradient the old
            // bubble used — that kept the light-mode teal in dark mode.
            gradient: AppTheme.primaryGrad(context),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppTheme.radiusLG),
              topRight: Radius.circular(AppTheme.radiusLG),
              bottomLeft: Radius.circular(AppTheme.radiusLG),
              bottomRight: Radius.circular(AppTheme.radiusXS),
            ),
          ),
          child: SelectionArea(
            child: Text(
              message.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.onGradient,
                    height: 1.45,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    if (message.hasFailed) return _failed(context);

    final body = streamingText == null
        ? ChatMarkdown(text: message.text)
        : ValueListenableBuilder<String>(
            valueListenable: streamingText!,
            builder: (context, value, _) => value.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChatMarkdown(text: value),
                      // A widget, not a '▌' concatenated into the markdown
                      // source — injected into the source it could land inside
                      // a table cell and change how the block parsed.
                      const _StreamingCursor(),
                    ],
                  ),
          );

    return Padding(
      padding: const EdgeInsets.only(
        top: AppTheme.spacingSM,
        bottom: AppTheme.spacingSM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(child: body),
          if (trailing != null) ...[
            const SizedBox(height: AppTheme.spacingMD),
            trailing!,
          ],
          if (!message.isStreaming && message.text.trim().isNotEmpty)
            _actions(context),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingXS),
      child: Row(
        children: [
          // There was no per-message copy at all before — only a whole-
          // transcript dump in the app bar.
          ChatCopyButton(text: message.text, label: 'Copy', dense: true),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(
                Icons.refresh_rounded,
                size: 15,
                color: AppTheme.textTer(context),
              ),
              label: Text(
                'Retry',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppTheme.textTer(context)),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          const Spacer(),
          Text(
            AppDates.shortDay.format(message.createdAt),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppTheme.textMute(context)),
          ),
        ],
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final danger = AppTheme.danger(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        decoration: BoxDecoration(
          color: AppTheme.tint(context, danger),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, size: 19, color: danger),
            const SizedBox(width: AppTheme.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text.isEmpty
                        ? "Couldn't reach the assistant."
                        : message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPri(context),
                        ),
                  ),
                  if (onRetry != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.spacingSM),
                      child: TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Try again'),
                        style: TextButton.styleFrom(
                          foregroundColor: danger,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A blinking block that marks where the answer is still being written.
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: FadeTransition(
        opacity: _c.drive(Tween(begin: 0.25, end: 1.0)),
        child: Container(
          width: 8,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primary(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
