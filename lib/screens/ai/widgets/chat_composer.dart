import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';

/// The message box.
///
/// Three fixes over the previous composer:
///
/// * it was **single-line** — no `maxLines`, no `minLines` — so a long question
///   scrolled sideways in a one-line field while being typed;
/// * the send button's callback went null during generation but kept its full
///   gradient and shadow, so it still looked tappable. There is now a real
///   **stop** button in its place;
/// * Enter sends on desktop and web, where Enter is the expected send key,
///   while Shift+Enter always makes a newline.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onStop,
    required this.isGenerating,
    this.onMicPressed,
    this.isListening = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final bool isGenerating;
  final VoidCallback? onMicPressed;
  final bool isListening;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Redraws the send button as text is typed, so it can be disabled while the
    // field is empty.
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _canSend =>
      !widget.isGenerating && widget.controller.text.trim().isNotEmpty;

  void _send() {
    if (!_canSend) return;
    widget.onSend(widget.controller.text.trim());
  }

  /// Enter sends where a hardware keyboard is the norm. On a phone Enter has to
  /// stay a newline, or a multiline composer is unusable.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final desktop = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!desktop || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingSM,
        AppTheme.spacingSM,
        AppTheme.spacingSM,
        AppTheme.spacingSM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: AppTheme.dividerC(context)),
        boxShadow: AppTheme.shadowFor(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.onMicPressed != null)
            IconButton(
              tooltip: widget.isListening ? 'Stop listening' : 'Speak',
              onPressed: widget.onMicPressed,
              icon: Icon(
                widget.isListening
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                size: 21,
                color: widget.isListening
                    ? AppTheme.danger(context)
                    : AppTheme.textTer(context),
              ),
            ),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                // Grows with the question instead of scrolling sideways.
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Ask about your stock…',
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textMute(context),
                      ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingXS),
          widget.isGenerating
              ? _RoundButton(
                  tooltip: 'Stop generating',
                  icon: Icons.stop_rounded,
                  background: AppTheme.inputFill(context),
                  foreground: AppTheme.textPri(context),
                  onPressed: widget.onStop,
                )
              : _RoundButton(
                  tooltip: 'Send',
                  icon: Icons.arrow_upward_rounded,
                  // Visibly inert when there is nothing to send, rather than
                  // fully saturated with a null callback.
                  background: _canSend
                      ? accent
                      : AppTheme.dividerStrongC(context),
                  foreground: _canSend
                      ? AppTheme.onGradient
                      : AppTheme.textMute(context),
                  onPressed: _canSend ? _send : null,
                ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
  }
}
