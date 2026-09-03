import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../config/theme.dart';

/// Renders an assistant answer.
///
/// The answers this receives are markdown prose, bullet lists and — often —
/// wide inventory tables. Three things the previous renderer got wrong:
///
/// * tables were boxed at `maxHeight: 280` inside a *vertical* scroll view
///   nested in the transcript's own vertical scroll view, wrapped in a
///   `Listener` that hijacked pointer moves. Dragging to select text inside a
///   table fought the drag-to-scroll handler. Tables now scroll horizontally
///   only, and selection works.
/// * two `ScrollController`s were allocated per table *inside a build method*
///   and never disposed. Each table now owns its controller in a State.
/// * the block split re-ran on every rebuild, which during streaming meant
///   re-splitting every message on screen on every token. Blocks are parsed
///   once per distinct string — see [_blockCache].
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text, this.selectable = true});

  final String text;

  /// The transcript wraps assistant turns in a `SelectionArea`; a nested
  /// selectable Markdown would compete with it.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingMD),
          if (blocks[i].isTable)
            _MarkdownTable(source: blocks[i].text)
          else
            MarkdownBody(
              data: blocks[i].text,
              selectable: false,
              shrinkWrap: true,
              softLineBreak: true,
              styleSheet: chatMarkdownStyle(context),
            ),
        ],
      ],
    );
  }
}

/// One markdown block: either a GFM table or everything else.
class _Block {
  const _Block(this.text, {this.isTable = false});
  final String text;
  final bool isTable;
}

/// Parsed blocks, keyed by the exact source string.
///
/// Streaming appends to the same message repeatedly, so without this the split
/// runs again for every visible message on every token. Bounded so a long
/// session cannot grow it without limit.
final Map<String, List<_Block>> _blockCache = {};
const int _blockCacheMax = 120;

final RegExp _tableSeparator = RegExp(r'^[\s\-:|]+$');

List<_Block> _parseBlocks(String source) {
  final hit = _blockCache[source];
  if (hit != null) return hit;

  final lines = source.split('\n');
  final blocks = <_Block>[];
  final buffer = <String>[];

  void flushText() {
    if (buffer.isEmpty) return;
    final joined = buffer.join('\n').trim();
    if (joined.isNotEmpty) blocks.add(_Block(joined));
    buffer.clear();
  }

  var i = 0;
  while (i < lines.length) {
    // A GFM table is recognised by its `|---|` separator: expand outwards from
    // it over every neighbouring line that contains a pipe.
    final isSeparator = lines[i].contains('|') &&
        lines[i].contains('-') &&
        _tableSeparator.hasMatch(lines[i].trim());

    if (isSeparator && i > 0 && lines[i - 1].contains('|')) {
      var start = i - 1;
      while (start > 0 && lines[start - 1].contains('|')) {
        start--;
      }
      var end = i;
      while (end + 1 < lines.length && lines[end + 1].contains('|')) {
        end++;
      }
      // Anything buffered before the table belongs to the preceding block, but
      // the header row was already swallowed into `buffer`.
      final headerRows = i - start;
      for (var k = 0; k < headerRows && buffer.isNotEmpty; k++) {
        buffer.removeLast();
      }
      flushText();
      blocks.add(_Block(lines.sublist(start, end + 1).join('\n'), isTable: true));
      i = end + 1;
      continue;
    }

    buffer.add(lines[i]);
    i++;
  }
  flushText();

  final result = blocks.isEmpty ? [_Block(source)] : blocks;
  if (_blockCache.length >= _blockCacheMax) _blockCache.clear();
  _blockCache[source] = result;
  return result;
}

/// A table, bordered and edge-to-edge on a phone.
///
/// It deliberately adds **no scroll view of its own**. `flutter_markdown`
/// already wraps a table in a horizontal `SingleChildScrollView`; nesting a
/// second one around it meant the inner one — the one closest to the pointer,
/// and the one that actually receives the drag — was handed unbounded width,
/// so it had nothing to scroll and swallowed every gesture. The outer one held
/// all the overflow and never saw a touch. That is why table scrolling
/// appeared broken.
class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dividerC(context)),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      clipBehavior: Clip.antiAlias,
      child: MarkdownBody(
        data: source,
        selectable: false,
        shrinkWrap: true,
        styleSheet: chatMarkdownStyle(context).copyWith(
          // Intrinsic, so a wide table keeps its columns legible and overflows
          // into the built-in scroller rather than squeezing to fit.
          tableColumnWidth: const IntrinsicColumnWidth(),
        ),
      ),
    );
  }
}

/// The shared markdown style for assistant answers.
///
/// Sizes come from the text theme rather than the literals the old sheet used,
/// and the accent is `AppTheme.primary(context)` — the previous sheet used the
/// const `primaryColor`, which is the light-mode teal and sat at poor contrast
/// on the dark ground.
MarkdownStyleSheet chatMarkdownStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final accent = AppTheme.primary(context);
  final body = t.bodyLarge!.copyWith(
    color: AppTheme.textPri(context),
    height: 1.6,
  );

  return MarkdownStyleSheet(
    p: body,
    h1: t.headlineSmall,
    h2: t.titleLarge,
    h3: t.titleMedium,
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    code: TextStyle(
      color: accent,
      fontSize: (body.fontSize ?? 16) - 2,
      fontWeight: FontWeight.w600,
      fontFamily: 'monospace',
      backgroundColor: AppTheme.tint(context, accent),
    ),
    codeblockPadding: const EdgeInsets.all(AppTheme.spacingMD),
    codeblockDecoration: BoxDecoration(
      color: AppTheme.inputFill(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      border: Border.all(color: AppTheme.dividerC(context)),
    ),
    blockquote: body.copyWith(color: AppTheme.textSec(context)),
    blockquotePadding: const EdgeInsets.only(left: AppTheme.spacingMD),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    a: TextStyle(color: accent, decoration: TextDecoration.underline),
    listBullet: body.copyWith(color: accent, fontWeight: FontWeight.w600),
    listIndent: 20,
    listBulletPadding: const EdgeInsets.only(right: 8),
    pPadding: EdgeInsets.zero,
    blockSpacing: AppTheme.spacingMD,
    tableBorder: TableBorder(
      horizontalInside: BorderSide(color: AppTheme.dividerC(context), width: 0.5),
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    tableBody: t.bodyMedium!.copyWith(color: AppTheme.textPri(context)),
    tableHead: t.labelMedium!.copyWith(
      color: AppTheme.textSec(context),
      fontWeight: FontWeight.w700,
    ),
    tableColumnWidth: const IntrinsicColumnWidth(),
  );
}

/// Copies [text] and briefly confirms it, following the pattern in
/// `document_sheet.dart` — a snackbar would be wrong here because the chat
/// already uses the bottom of the screen for the composer.
class ChatCopyButton extends StatefulWidget {
  const ChatCopyButton({
    super.key,
    required this.text,
    this.label,
    this.dense = false,
  });

  final String text;
  final String? label;
  final bool dense;

  @override
  State<ChatCopyButton> createState() => _ChatCopyButtonState();
}

class _ChatCopyButtonState extends State<ChatCopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final icon = _copied ? Icons.check_rounded : Icons.copy_rounded;
    final color =
        _copied ? AppTheme.success(context) : AppTheme.textTer(context);

    if (widget.label == null) {
      return IconButton(
        tooltip: _copied ? 'Copied' : 'Copy',
        icon: Icon(icon, size: 16, color: color),
        visualDensity: VisualDensity.compact,
        onPressed: _copy,
      );
    }

    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(icon, size: 15, color: color),
      label: Text(
        _copied ? 'Copied' : widget.label!,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.symmetric(
          horizontal: widget.dense ? 8 : 12,
          vertical: 6,
        ),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
