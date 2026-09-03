import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../services/rag_api_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_markdown.dart';
import 'widgets/chat_message_view.dart';
import 'widgets/chat_payload_cards.dart';
import 'widgets/chat_status.dart';

/// Ask AI.
///
/// Replaces a 2,595-line screen. The behavioural changes that matter:
///
/// * a streamed token repaints **one** widget. Live text lives in
///   [_streamingText]; previously every delta called `setState` on the screen,
///   which re-ran the markdown split for every message on it.
/// * the stream subscription is held and cancelled, on stop and on dispose. It
///   used to be abandoned with `if (!mounted) return`, leaving it running.
/// * a failure is a failure — an error surface with Retry, not a sentence in an
///   assistant bubble that reads like an answer.
/// * the status line shows the backend's real `status` frames instead of canned
///   reasoning steps picked by keyword-matching the question.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, this.askStream, this.contextBuilder});

  /// The answer stream. Defaults to [RagApiService.askQuestionStream].
  ///
  /// Injectable because the service is a set of statics over `http`, which made
  /// this screen impossible to render in a test at all.
  final AskStream? askStream;

  /// Builds the counters sent alongside the question. Defaults to reading the
  /// inventory providers, which cannot be constructed without Firebase.
  final Future<String> Function(BuildContext context)? contextBuilder;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

/// Signature of [RagApiService.askQuestionStream].
typedef AskStream = Stream<Map<String, dynamic>> Function(
  String question, {
  String context,
  List<Map<String, String>> history,
});

class _AiChatScreenState extends State<AiChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Live answer text. A notifier so only the streaming turn listens.
  final ValueNotifier<String> _streamingText = ValueNotifier('');

  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _isGenerating = false;

  /// Backend status frames for the answer in flight, oldest first. Accumulated
  /// so the indicator can show what is finished as well as what is running.
  final List<String> _statusSteps = [];

  String? _lastQuery;

  /// Whether the transcript is parked at the bottom.
  ///
  /// Auto-scroll is conditional on this: the old screen animated to the bottom
  /// on every token, so scrolling up to read while an answer streamed was
  /// impossible.
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  @override
  void dispose() {
    // The previous screen never cancelled this, so a stream outlived the route.
    _subscription?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    _streamingText.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  String? get _historyKey {
    try {
      final uid = context.read<AuthProvider>().currentUser?.uid;
      return uid == null ? null : 'chat_history_$uid';
    } catch (_) {
      // No auth provider in scope. History is a convenience; the chat itself
      // must still work.
      return null;
    }
  }

  Future<void> _saveHistory() async {
    final key = _historyKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        key,
        _messages.map((m) => jsonEncode(m.toJson())).toList(),
      );
    } catch (_) {
      // History is a convenience; losing it must not interrupt the chat.
    }
  }

  Future<void> _loadHistory() async {
    final key = _historyKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(key);
      if (stored == null || stored.isEmpty) return;
      final restored = <ChatMessage>[];
      for (final row in stored) {
        try {
          restored.add(ChatMessage.fromJson(jsonDecode(row) as Map<String, dynamic>));
        } catch (_) {
          // Skip one unreadable record rather than losing the transcript.
        }
      }
      if (!mounted || restored.isEmpty) return;
      setState(() => _messages.addAll(restored));
      _scrollToBottom(force: true);
    } catch (_) {
      // As above.
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// The counters the backend cannot cheaply infer.
  ///
  /// Trimmed: this used to also send ten low-stock product lines, which the
  /// backend recomputes from Firestore in `facts.summary_line()` and then
  /// truncates to 800 characters anyway.
  Future<String> _buildContext() async {
    final override = widget.contextBuilder;
    if (override != null) return override(context);
    final products = context.read<ProductProvider>();
    if (!products.isAnalyticsLoaded) {
      await products.loadAnalytics();
    }
    if (!mounted) return '';
    final sales = context.read<SalesOrderProvider>();
    final purchases = context.read<PurchaseOrderProvider>();
    return 'INVENTORY STATS: Total Products: ${products.totalProducts} | '
        'Low Stock Alerts: ${products.lowStockCount} | '
        'Out of Stock: ${products.outOfStockCount} | '
        'Pending Sales Orders: ${sales.orders.where((o) => o.status.name == 'confirmed').length} | '
        'Pending Purchase Orders: ${purchases.orders.where((o) => o.status.name == 'sent').length}';
  }

  List<Map<String, String>> _historyPayload() {
    final tableLine = RegExp(r'^\s*\|.*\|\s*$', multiLine: true);
    final tagged = RegExp(r'\[(?:STATS|ACTION|PENDING):.*?\]', dotAll: true);
    final blankRuns = RegExp(r'\n{3,}');

    // Drops the turn just added, and any failed turn — a failure is not part of
    // the conversation the model should reason over.
    final source = _messages
        .take(_messages.length > 0 ? _messages.length - 1 : 0)
        .where((m) => !m.hasFailed);

    final recent = source.length > 12
        ? source.skip(source.length - 12).toList()
        : source.toList();

    final payload = <Map<String, String>>[];
    for (final m in recent) {
      var content = m.text.replaceAll(tagged, '').replaceAll(tableLine, '');
      content = content.replaceAll(blankRuns, '\n\n').trim();
      if (content.isEmpty) continue;
      if (content.length > 600) {
        content = '${content.substring(0, 600).trimRight()}...';
      }
      payload.add({'role': m.isUser ? 'user' : 'model', 'content': content});
    }
    return payload;
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _isGenerating) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    setState(() {
      _lastQuery = question;
      _messages.add(ChatMessage(text: question, role: ChatRole.user));
      _isGenerating = true;
      _statusSteps.clear();
    });
    _streamingText.value = '';
    _scrollToBottom(force: true);
    unawaited(_saveHistory());

    final history = _historyPayload();
    final contextText = await _buildContext();
    if (!mounted) return;

    // The placeholder the deltas flow into. It stays `streaming` until done, so
    // the transcript can render the cursor against it.
    final placeholder = ChatMessage(
      text: '',
      role: ChatRole.assistant,
      status: ChatStatus.streaming,
    );
    setState(() => _messages.add(placeholder));

    final buffer = StringBuffer();
    RagResponse? finalResponse;
    var sawDone = false;

    // Not awaited. `askQuestionStream` is an `async*` generator, and cancelling
    // a subscription whose generator has already finished returns a future that
    // never completes — so awaiting it here meant the *second* message of every
    // conversation was never sent. Confirming a previewed change is always a
    // second message, so that path could never fire at all.
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _subscription = null;

    final completer = Completer<void>();

    final ask = widget.askStream ?? RagApiService.askQuestionStream;
    _subscription = ask(
      question,
      context: contextText,
      history: history,
    ).listen(
      (event) {
        switch (event['type']) {
          case 'status':
            final msg = (event['message'] as String?)?.trim();
            if (mounted && msg != null && msg.isNotEmpty) {
              // Duplicates arrive when a step is re-announced; they would show
              // as a repeated line.
              if (_statusSteps.isEmpty || _statusSteps.last != msg) {
                setState(() => _statusSteps.add(msg));
              }
            }
          case 'delta':
            buffer.write(event['content'] ?? '');
            // Only the streaming turn rebuilds.
            _streamingText.value = buffer.toString();
            _scrollToBottom();
          case 'reset':
            // The server fell back to non-streaming; discard partial text so it
            // cannot concatenate with the final answer.
            buffer.clear();
            _streamingText.value = '';
          case 'done':
            sawDone = true;
            finalResponse = event['response'] as RagResponse?;
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
    if (!mounted) return;

    final response = finalResponse;
    final streamed = buffer.toString().trim();

    setState(() {
      final index = _messages.indexWhere((m) => m.id == placeholder.id);
      if (index == -1) return;

      if (response != null) {
        _messages[index] = placeholder.copyWith(
          text: response.text,
          status: ChatStatus.complete,
          actionPayload: response.actionPayload,
          statsPayload: response.statsPayload,
          itemsPayload: response.items,
          clarificationOptions: response.clarificationOptions,
          pendingAction: response.pendingAction,
          responseKind: response.responseKind,
          answeredBy: response.answeredBy,
        );
      } else if (sawDone && streamed.isNotEmpty) {
        _messages[index] =
            placeholder.copyWith(text: streamed, status: ChatStatus.complete);
      } else {
        // No answer arrived. Previously this became an ordinary assistant
        // sentence with no way to retry.
        _messages[index] = placeholder.copyWith(
          text: "Couldn't reach the assistant.",
          status: ChatStatus.failed,
        );
      }
      _isGenerating = false;
      _statusSteps.clear();
    });

    _streamingText.value = '';
    _scrollToBottom();
    unawaited(_saveHistory());

    // A write the assistant performed changes the numbers the rest of the app
    // is showing, so refresh them.
    final executed = response?.executedActions ?? const [];
    if (executed.isNotEmpty && mounted) {
      unawaited(context.read<ProductProvider>().loadAnalytics());
    }
  }

  void _stop() {
    _subscription?.cancel();
    final partial = _streamingText.value.trim();
    setState(() {
      final index = _messages.lastIndexWhere((m) => m.isStreaming);
      if (index != -1) {
        _messages[index] = partial.isEmpty
            // Nothing arrived, so leave nothing behind.
            ? _messages[index].copyWith(
                text: 'Stopped.',
                status: ChatStatus.complete,
              )
            : _messages[index]
                .copyWith(text: partial, status: ChatStatus.complete);
      }
      _isGenerating = false;
      _statusSteps.clear();
    });
    _streamingText.value = '';
    unawaited(_saveHistory());
  }

  Future<void> _retry() async {
    final query = _lastQuery;
    if (query == null || _isGenerating) return;
    setState(() {
      // Drop the failed turn and the question, then ask it again.
      if (_messages.isNotEmpty && !_messages.last.isUser) _messages.removeLast();
      if (_messages.isNotEmpty && _messages.last.isUser) _messages.removeLast();
    });
    await _send(query);
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear this conversation?',
      message: 'The whole transcript is deleted. This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _messages.clear();
      _lastQuery = null;
    });
    final key = _historyKey;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    }
    unawaited(RagApiService.clearCache());
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  Widget? _trailingFor(ChatMessage m) {
    // A bulk change lists every affected product inside its own confirm card,
    // so the generic item list would repeat it.
    final isBulk = m.pendingAction?['tool'] == '__bulk__';

    final cards = <Widget>[
      if (m.statsPayload != null) ChatStatsCard(stats: m.statsPayload!),
      if (!isBulk && m.itemsPayload != null && m.itemsPayload!.isNotEmpty)
        ChatItemListCard(items: m.itemsPayload!, kind: m.responseKind),
      if (m.responseKind == 'no_history') const ChatNoHistoryCard(),
      if (m.pendingAction != null && !m.isActionExecuted)
        if (isBulk)
          ChatBulkConfirmCard(
            action: m.pendingAction!,
            onDecision: (confirmed) => _send(confirmed ? 'confirm' : 'cancel'),
          )
        else
          ChatConfirmCard(
            action: m.pendingAction!,
            onDecision: (confirmed) => _send(confirmed ? 'confirm' : 'cancel'),
          ),
      if (m.clarificationOptions != null && m.clarificationOptions!.isNotEmpty)
        ChatClarificationChips(
          options: m.clarificationOptions!,
          onSelected: (option) => _send(
            option['barcode']?.toString() ?? option['name']?.toString() ?? '',
          ),
        ),
    ];
    if (cards.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingMD),
          cards[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tighter than Responsive.horizontalPadding on a phone. A transcript is
    // mostly long prose and wide tables, and 16px of gutter each side is 9% of
    // a 360dp screen spent on nothing. Desktop keeps a comfortable gutter.
    final narrow = Responsive.isMobile(context);
    final pad = narrow ? 12.0 : Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.auto_awesome_rounded,
          color: AppTheme.primary(context),
          title: 'Ask AI',
        ),
        actions: [
          if (_messages.isNotEmpty) ...[
            ChatCopyButton(
              text: _messages
                  .map((m) => '${m.isUser ? 'You' : 'Ask AI'}: ${m.text}')
                  .join('\n\n'),
            ),
            IconButton(
              tooltip: 'Clear conversation',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _clear,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      if (_messages.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: pad),
                          child: ChatEmptyState(onPick: _send),
                        )
                      else
                        ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(pad, 8, pad, 16),
                          itemCount: _messages.length + (_isGenerating ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _messages.length) {
                              return ChatStatusIndicator(
                                steps: List.unmodifiable(_statusSteps),
                              );
                            }
                            final m = _messages[i];
                            final isLast = i == _messages.length - 1;
                            return ChatMessageView(
                              key: ValueKey(m.id),
                              message: m,
                              streamingText:
                                  m.isStreaming ? _streamingText : null,
                              trailing: _trailingFor(m),
                              onRetry: m.hasFailed && isLast ? _retry : null,
                            );
                          },
                        ),
                      if (!_atBottom && _messages.isNotEmpty)
                        Positioned(
                          right: pad,
                          bottom: 8,
                          child: _ScrollToBottomButton(
                            onPressed: () => _scrollToBottom(force: true),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 4, pad, 10),
                  child: ChatComposer(
                    controller: _controller,
                    onSend: _send,
                    onStop: _stop,
                    isGenerating: _isGenerating,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface(context),
      shape: CircleBorder(
        side: BorderSide(color: AppTheme.dividerC(context)),
      ),
      elevation: AppTheme.isDark(context) ? 0 : 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.arrow_downward_rounded,
            size: 18,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }
}
