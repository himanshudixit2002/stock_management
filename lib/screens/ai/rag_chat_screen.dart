import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/chat_session_model.dart';
import '../../models/sales_order_model.dart';
import '../../models/purchase_order_model.dart';
import '../../services/rag_api_service.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../widgets/floating_nav_padding.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key});

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollToBottom == isAtBottom) {
      setState(() => _showScrollToBottom = !isAtBottom);
    }
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening() async {
    await _speechToText.listen(onResult: (result) {
      setState(() {
        _controller.text = result.recognizedWords;
      });
      if (result.finalResult) {
        _stopListening();
        // Auto-send after 2 seconds of silence
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _controller.text.trim().isNotEmpty) {
            _sendMessage();
          }
        });
      }
    });
    setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  // ── Context Building ─────────────────────────────────────────────────────

  Future<String> _buildContext(String lowerText) async {
    final provider = context.read<ProductProvider>();
    final salesProvider = context.read<SalesOrderProvider>();
    final purchaseProvider = context.read<PurchaseOrderProvider>();

    if (!provider.isAnalyticsLoaded) {
      await provider.loadAnalytics();
    }

    final allProducts = provider.analyticsProducts;
    final totalItems = allProducts.length;
    final lowStockCount = provider.lowStockProducts.length;
    final outOfStockCount = allProducts.where((p) => p.isOutOfStock).length;
    final pendingSales = salesProvider.orders
        .where((o) =>
            o.status != SOStatus.delivered && o.status != SOStatus.cancelled)
        .length;
    final pendingPurchase = purchaseProvider.orders
        .where((o) =>
            o.status != POStatus.received && o.status != POStatus.cancelled)
        .length;

    String intentContext = '';
    List<dynamic> relevantProducts = [];

    if (lowerText.contains('summary') ||
        lowerText.contains('overview') ||
        lowerText.contains('total') ||
        lowerText.contains('how many') ||
        lowerText.contains('stats') ||
        lowerText.contains('kitna') ||
        lowerText.contains('sab batao') ||
        lowerText.contains('pura stock')) {
      intentContext =
          '[SYSTEM: User wants an overview. They might speak Hinglish (Hindi in English). Answer naturally. Provide a sharp 1-sentence summary based on these stats: Total Products: $totalItems, Low Stock: $lowStockCount, Out of Stock: $outOfStockCount, Pending Sales: $pendingSales, Pending Purchase Orders: $pendingPurchase]';
    } else if (lowerText.contains('low') ||
        lowerText.contains('restock') ||
        lowerText.contains('out of stock') ||
        lowerText.contains('khatam') ||
        lowerText.contains('kam hai') ||
        lowerText.contains('mangwana')) {
      relevantProducts = provider.lowStockProducts.take(10).toList();
      if (relevantProducts.isEmpty) {
        intentContext =
            '[SYSTEM: User asked for restocking advice (possibly in Hinglish). Their inventory is perfectly healthy! Congratulate them in 1 sentence.]';
      } else {
        intentContext =
            '[SYSTEM: Focus on urgent restocking. They might speak Hinglish. Here are the most critical low stock items:]';
      }
    } else if (lowerText.contains('sale') ||
        lowerText.contains('purchase') ||
        lowerText.contains('order') ||
        lowerText.contains('bikri') ||
        lowerText.contains('kharid')) {
      intentContext =
          '[SYSTEM: User asked about orders (possibly in Hinglish). We currently have $pendingSales pending sales and $pendingPurchase pending purchase orders.]';
    } else {
      relevantProducts = allProducts
          .where((p) =>
              lowerText.contains(p.name.toLowerCase()) ||
              lowerText.contains(p.barcode.toLowerCase()) ||
              p.categoryName.toLowerCase().contains(lowerText))
          .take(5)
          .toList();

      if (relevantProducts.isEmpty && allProducts.isNotEmpty) {
        intentContext =
            '[SYSTEM: General query. Answer smartly using these sample products and overall stats (Total: $totalItems, Low: $lowStockCount)]';
        relevantProducts = allProducts.take(5).toList();
      }
    }

    final productContext = relevantProducts.isEmpty
        ? ''
        : relevantProducts
            .map((p) =>
                '${p.name}(BC:${p.barcode},Qty:${p.quantity},Min:${p.lowStockThreshold})')
            .join(' | ');

    return '$intentContext $productContext'.trim();
  }

  // ── Send Message ─────────────────────────────────────────────────────────

  void _sendMessage([String? predefinedText]) async {
    final chatProvider = context.read<ChatProvider>();
    final text = predefinedText ?? _controller.text.trim();
    if (text.isEmpty) return;

    final lowerText = text.toLowerCase();
    HapticFeedback.lightImpact();

    chatProvider.addUserMessage(text);
    chatProvider.setLoading(true);
    if (predefinedText == null) _controller.clear();
    _scrollToBottom();

    // Zero-token interceptor for greetings (includes Hinglish!)
    final greetings = [
      'hi', 'hello', 'hey', 'help', 'who are you', 'how are you',
      'namaste', 'kaise ho', 'kya haal', 'aur batao',
    ];
    if (greetings.contains(lowerText)) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        HapticFeedback.mediumImpact();
        chatProvider.setLoading(false);
        chatProvider.addBotMessage(ChatMessage(
          text:
              "Hi! I'm Nova, your Inventory AI. Ask me about stock levels or restocking, and I'll keep it brief!",
          isUser: false,
        ));
        _scrollToBottom();
      }
      return;
    }

    // Zero-token interceptor for navigation
    if (lowerText.contains('open ') ||
        lowerText.contains('go to ') ||
        lowerText.contains('show me ')) {
      String? target;
      if (lowerText.contains('billing') ||
          lowerText.contains('pos') ||
          lowerText.contains('sale')) {
        target = 'billing';
      } else if (lowerText.contains('order')) {
        target = 'orders';
      } else if (lowerText.contains('product') ||
          lowerText.contains('item')) {
        target = 'products';
      } else if (lowerText.contains('audit') ||
          lowerText.contains('stock take')) {
        target = 'audit';
      } else if (lowerText.contains('report')) {
        target = 'reports';
      }

      if (target != null) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          HapticFeedback.mediumImpact();
          chatProvider.setLoading(false);
          chatProvider.addBotMessage(ChatMessage(
            text: 'Sure, let me take you there.',
            isUser: false,
            actionPayload: {'type': 'navigate', 'target': target},
          ));
          _scrollToBottom();
        }
        return;
      }
    }

    // Build context and call API
    try {
      final contextText = await _buildContext(lowerText);
      chatProvider.setLoading(false);
      chatProvider.startStreaming();

      String finalText = '';

      await for (final chunk in RagApiService.askQuestionStream(
        text,
        context: contextText.isNotEmpty ? contextText : 'No inventory data found.',
        chatHistory: chatProvider.getChatHistory(),
      )) {
        chatProvider.appendStreamChunk(chunk);
        finalText += chunk;
        if (mounted) {
           _scrollToBottom();
        }
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        
        // Parse legacy action if present in finalText
        Map<String, dynamic>? actionPayload;
        final actionRegex = RegExp(r'\[ACTION:\s*({.*?})\s*\]', dotAll: true);
        final match = actionRegex.firstMatch(finalText);
        if (match != null) {
          try {
            final jsonStr = match.group(1)!;
            actionPayload = jsonDecode(jsonStr) as Map<String, dynamic>;
            finalText = finalText.replaceFirst(match.group(0)!, '').trim();
          } catch (e) {
            debugPrint('Failed to parse legacy action JSON: $e');
          }
        }
        
        chatProvider.finalizeStream(ChatMessage(
          text: finalText,
          isUser: false,
          actionPayload: actionPayload,
        ));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        chatProvider.setLoading(false);
        chatProvider.addBotMessage(ChatMessage(
          text:
              "Sorry, I couldn't reach the server. Please ensure the backend is running.",
          isUser: false,
        ));
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          drawer: _buildSessionDrawer(context, chatProvider),
          appBar: _buildAppBar(context, chatProvider),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: chatProvider.messages.isEmpty
                        ? _buildEmptyState(context)
                        : _buildMessageList(context, chatProvider),
                  ),
                  if (chatProvider.isLoading)
                    _buildLoadingIndicator(context),
                  if (chatProvider.isStreaming)
                    _buildStreamingBubble(context, chatProvider),
                  _buildSmartSuggestions(context, chatProvider),
                  _buildInputArea(context, chatProvider),
                ],
              ),
              // Scroll-to-bottom FAB
              if (_showScrollToBottom)
                Positioned(
                  right: 16,
                  bottom: 200,
                  child: FloatingActionButton.small(
                    heroTag: 'scroll_bottom',
                    onPressed: _scrollToBottom,
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.9),
                    child:
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  )
                      .animate()
                      .fade(duration: 200.ms)
                      .scale(begin: const Offset(0.8, 0.8)),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      BuildContext context, ChatProvider chatProvider) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            title: const Text('Nova AI',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.bg(context).withValues(alpha: 0.7),
            elevation: 0,
            centerTitle: true,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'Chat History',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_comment_rounded),
                tooltip: 'New Chat',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  chatProvider.startNewSession();
                  _scrollToBottom();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Clear Chat',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  chatProvider.startNewSession();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Session Drawer ───────────────────────────────────────────────────────

  Widget _buildSessionDrawer(
      BuildContext context, ChatProvider chatProvider) {
    return Drawer(
      backgroundColor: AppTheme.bg(context),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nova AI',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text('Chat History',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.add_rounded, color: Colors.white),
                    onPressed: () {
                      chatProvider.startNewSession();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            // Session list
            Expanded(
              child: chatProvider.sessions.isEmpty
                  ? Center(
                      child: Text('No conversations yet',
                          style: TextStyle(color: AppTheme.textMute(context))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: chatProvider.sessions.length,
                      itemBuilder: (context, index) {
                        final session = chatProvider.sessions[index];
                        final isActive =
                            session.id == chatProvider.currentSession?.id;
                        return Dismissible(
                          key: Key(session.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: AppTheme.dangerColor,
                            child: const Icon(Icons.delete_rounded,
                                color: Colors.white),
                          ),
                          onDismissed: (_) =>
                              chatProvider.deleteSession(session.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor:
                                AppTheme.primaryColor.withValues(alpha: 0.1),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppTheme.primaryColor
                                        .withValues(alpha: 0.15)
                                    : AppTheme.surface(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: isActive
                                    ? AppTheme.primaryColor
                                    : AppTheme.textMute(context),
                              ),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                            subtitle: Text(
                              '${session.messageCount} messages',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMute(context)),
                            ),
                            onTap: () {
                              chatProvider.switchSession(session.id);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final suggestions = [
      _EmptySuggestion('Inventory Overview', Icons.pie_chart_rounded,
          'Give me a summary of my inventory'),
      _EmptySuggestion('Low Stock Items', Icons.warning_rounded,
          'What items are low in stock?'),
      _EmptySuggestion('Pending Orders', Icons.receipt_long_rounded,
          'Show me pending orders'),
      _EmptySuggestion('Sales Analytics', Icons.trending_up_rounded,
          'Show me the sales trend'),
    ];

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
        left: 24,
        right: 24,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nova icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 40),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 2500.ms, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(height: 24),
              Text(
                "Hi! I'm Nova",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPri(context),
                  letterSpacing: -0.5,
                ),
              ).animate().fade(duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: 8),
              Text(
                'Your intelligent inventory assistant',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSec(context),
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fade(delay: 200.ms, duration: 500.ms),
              const SizedBox(height: 36),
              // Suggestion cards grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: suggestions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  return _buildSuggestionCard(context, s, idx);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(
      BuildContext context, _EmptySuggestion suggestion, int index) {
    return GestureDetector(
      onTap: () => _sendMessage(suggestion.prompt),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface(context).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(suggestion.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              suggestion.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPri(context),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fade(delay: (200 + index * 100).ms, duration: 400.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
  }

  // ── Message List ─────────────────────────────────────────────────────────

  Widget _buildMessageList(
      BuildContext context, ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
        bottom: 16,
        left: 16,
        right: 16,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _ChatBubble(
          message: message,
          onSendMessage: _sendMessage,
        )
            .animate()
            .fade(duration: 300.ms)
            .slideY(begin: 0.05, end: 0, curve: Curves.easeOutQuad);
      },
    );
  }

  // ── Loading Indicator ────────────────────────────────────────────────────

  Widget _buildLoadingIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 24.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    AppTheme.surface(context).withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                    color:
                        AppTheme.primaryColor.withValues(alpha: 0.3),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.primaryColor
                          .withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppTheme.primaryColor, size: 16),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 1500.ms, color: Colors.white)
                .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.1, 1.1),
                    duration: 800.ms)
                .then()
                .scale(
                    begin: const Offset(1.1, 1.1),
                    end: const Offset(0.9, 0.9),
                    duration: 800.ms),
            const SizedBox(width: 14),
            const Text(
              'Analyzing inventory...',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            )
                .animate(
                    onPlay: (controller) =>
                        controller.repeat(reverse: true))
                .fade(begin: 0.4, end: 1.0, duration: 800.ms),
          ],
        ),
      ),
    );
  }

  // ── Streaming Bubble ─────────────────────────────────────────────────────

  Widget _buildStreamingBubble(
      BuildContext context, ChatProvider chatProvider) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildNovaAvatar(),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.surface(context).withValues(alpha: 0.85),
                      AppTheme.bg(context).withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color:
                          AppTheme.primaryColor.withValues(alpha: 0.2),
                      width: 1.5),
                  borderRadius: BorderRadius.circular(24).copyWith(
                      bottomLeft: const Radius.circular(4)),
                ),
                child: Text(
                  '${chatProvider.streamingText}▌',
                  style: TextStyle(
                    color: AppTheme.textPri(context),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Smart Suggestions ────────────────────────────────────────────────────

  Widget _buildSmartSuggestions(
      BuildContext context, ChatProvider chatProvider) {
    final suggestions = chatProvider.getSmartSuggestions();
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final s = suggestions[index];
          return _QuickActionChip(
            label: s.label,
            icon: s.icon,
            onTap: () => _sendMessage(s.prompt),
          )
              .animate()
              .fade(delay: (100 * index).ms, duration: 300.ms)
              .slideX(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
        },
      ),
    );
  }

  // ── Input Area ───────────────────────────────────────────────────────────

  Widget _buildInputArea(BuildContext context, ChatProvider chatProvider) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: keyboardOpen ? 8 : floatingNavContentInset(context),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    AppTheme.surface(context).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(
                            color: AppTheme.textPri(context),
                            fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Ask Nova...',
                          hintStyle: TextStyle(
                              color: AppTheme.textPri(context)
                                  .withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Voice button
                    Container(
                      decoration: BoxDecoration(
                        color: _isListening
                            ? AppTheme.dangerColor
                                .withValues(alpha: 0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: _isListening
                              ? AppTheme.dangerColor
                              : AppTheme.textSec(context),
                        ),
                        onPressed: () async {
                          if (!_speechEnabled) {
                            _speechEnabled =
                                await _speechToText.initialize();
                            if (!_speechEnabled) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Microphone not available.')));
                              }
                              return;
                            }
                          }
                          _speechToText.isNotListening
                              ? _startListening()
                              : _stopListening();
                        },
                      ),
                    )
                        .animate(target: _isListening ? 1 : 0)
                        .scale(
                            begin: const Offset(1, 1),
                            end: const Offset(1.15, 1.15)),
                    // Pulsing recording indicator
                    if (_isListening)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.dangerColor,
                          shape: BoxShape.circle,
                        ),
                      )
                          .animate(
                              onPlay: (c) => c.repeat(reverse: true))
                          .scale(
                              begin: const Offset(0.8, 0.8),
                              end: const Offset(1.3, 1.3),
                              duration: 600.ms)
                          .fade(begin: 0.5, end: 1.0, duration: 600.ms),
                    const SizedBox(width: 4),
                    // Send button
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                        onPressed: chatProvider.isLoading
                            ? null
                            : () => _sendMessage(),
                      ),
                    )
                        .animate()
                        .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutBack),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Nova Avatar ──────────────────────────────────────────────────────────

  Widget _buildNovaAvatar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: const Icon(Icons.auto_awesome_rounded,
          color: Colors.white, size: 16),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
            duration: 2000.ms,
            color: Colors.white.withValues(alpha: 0.8));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _EmptySuggestion {
  final String label;
  final IconData icon;
  final String prompt;
  _EmptySuggestion(this.label, this.icon, this.prompt);
}

// ── Quick Action Chip ──────────────────────────────────────────────────────

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionChip(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: AppTheme.surface(context).withValues(alpha: 0.8),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                      color:
                          AppTheme.primaryColor.withValues(alpha: 0.3),
                      width: 1.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chat Bubble ────────────────────────────────────────────────────────────

class _ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final void Function(String) onSendMessage;

  const _ChatBubble({required this.message, required this.onSendMessage});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _isExecuting = false;

  // ── Action Execution ─────────────────────────────────────────────────────

  void _executeAction(BuildContext context) async {
    final payload = widget.message.actionPayload;
    if (payload == null) return;

    final type = payload['type'];
    final barcode = payload['barcode'];
    final qtyChange = payload['qty_change'];

    if (type == 'update_stock' && barcode != null && qtyChange != null) {
      setState(() => _isExecuting = true);

      final provider = context.read<ProductProvider>();
      final stockProvider = context.read<StockProvider>();
      final authProvider = context.read<AuthProvider>();
      final user = authProvider.currentUser;

      final products = provider.analyticsProducts;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Session expired. Cannot update stock.')));
        }
        setState(() => _isExecuting = false);
        return;
      }

      try {
        final product =
            products.firstWhere((p) => p.barcode == barcode.toString());
        final int change = (qtyChange as num).toInt();

        final Map<String, int> locQty = product.locationQuantities;
        final String targetLocation =
            locQty.isNotEmpty ? locQty.keys.first : 'Default';

        bool success = false;
        const reason = 'AI Assistant Action';
        final aiUserName = '${user.name} (via AI)';

        if (change > 0) {
          success = await stockProvider.addStock(
            productId: product.id,
            productName: product.name,
            quantity: change,
            location: targetLocation,
            userId: user.uid,
            userName: aiUserName,
            reason: reason,
          );
        } else if (change < 0) {
          success = await stockProvider.removeStock(
            productId: product.id,
            productName: product.name,
            quantity: change.abs(),
            location: targetLocation,
            userId: user.uid,
            userName: aiUserName,
            reason: reason,
          );
        } else {
          success = true;
        }

        if (success) {
          setState(() => widget.message.isActionExecuted = true);
          HapticFeedback.heavyImpact();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to update stock.')));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Product not found in current inventory.')));
        }
      } finally {
        if (mounted) setState(() => _isExecuting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUser;
    final timestamp = widget.message.timestamp;
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    Widget bubble = GestureDetector(
      onLongPress: isUser
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: widget.message.text));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1)),
              );
            },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          gradient: isUser
              ? AppTheme.primaryGradient
              : LinearGradient(
                  colors: [
                    AppTheme.surface(context).withValues(alpha: 0.85),
                    AppTheme.bg(context).withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: isUser
              ? null
              : Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  width: 1.5),
          borderRadius: BorderRadius.circular(24).copyWith(
            bottomRight:
                isUser ? const Radius.circular(4) : const Radius.circular(24),
            bottomLeft:
                isUser ? const Radius.circular(24) : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: isUser
                  ? AppTheme.primaryColor.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            isUser
                ? Text(
                    widget.message.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : MarkdownBody(
                    data: widget.message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                          color: AppTheme.textPri(context),
                          fontSize: 15,
                          height: 1.4,
                          letterSpacing: 0.1),
                      strong: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 15),
                      listBullet: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                      blockSpacing: 8,
                      tableBorder: TableBorder.all(
                          color:
                              AppTheme.primaryColor.withValues(alpha: 0.3),
                          width: 1,
                          borderRadius: BorderRadius.circular(8)),
                      tableCellsPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      tableBody: TextStyle(
                          color: AppTheme.textPri(context), fontSize: 14),
                      tableHead: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: isUser
                    ? Colors.white.withValues(alpha: 0.6)
                    : AppTheme.textMute(context),
              ),
            ),
          ],
        ),
      ),
    );

    // Action card for bot messages with action payloads
    if (widget.message.actionPayload != null && !isUser) {
      final payload = widget.message.actionPayload!;
      final actionType = payload['type'] ?? 'unknown';

      Widget actionCard;
      if (actionType == 'update_stock') {
        actionCard = _buildStockUpdateCard(context, payload);
      } else if (actionType == 'create_purchase_order') {
        actionCard = _buildPurchaseOrderCard(context, payload);
      } else if (actionType == 'create_sales_order') {
        actionCard = _buildSalesOrderCard(context, payload);
      } else if (actionType == 'navigate') {
        actionCard = _buildNavigateCard(context, payload);
      } else if (actionType == 'generate_report') {
        actionCard = _buildReportCard(context, payload);
      } else {
        // Fallback: generic action card
        actionCard = _buildGenericActionCard(context, payload);
      }

      bubble = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bubble, actionCard],
      );
    }

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 12, bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color:
                          AppTheme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 16),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                    duration: 2000.ms,
                    color: Colors.white.withValues(alpha: 0.8)),
            Flexible(child: bubble),
          ],
        ),
      );
    }
  }

  // ── Action Card Builders ─────────────────────────────────────────────────

  Widget _buildActionCardShell({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12, left: 40),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.message.isActionExecuted
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : AppTheme.primaryColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.message.isActionExecuted
                    ? Icons.check_circle_rounded
                    : icon,
                color: widget.message.isActionExecuted
                    ? AppTheme.successColor
                    : iconColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.message.isActionExecuted
                    ? 'Action Executed'
                    : title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPri(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ).animate().fade(duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildStockUpdateCard(
      BuildContext context, Map<String, dynamic> payload) {
    final qty = payload['qty_change'] ?? 0;
    final actionDesc =
        (qty >= 0) ? 'Add $qty units' : 'Deduct ${(qty as num).abs()} units';

    return _buildActionCardShell(
      context: context,
      icon: Icons.inventory_rounded,
      iconColor: AppTheme.warningColor,
      title: 'Stock Update',
      children: [
        Text('Task: $actionDesc',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
        Text('Barcode: ${payload['barcode']}',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 13)),
        if (!widget.message.isActionExecuted) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => widget.message.isActionExecuted = true);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dangerColor,
                    side: const BorderSide(color: AppTheme.dangerColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      _isExecuting ? null : () => _executeAction(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: _isExecuting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Confirm & Execute'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseOrderCard(
      BuildContext context, Map<String, dynamic> payload) {
    final vendor = payload['vendor'] ?? 'Unknown Vendor';
    final items = payload['items'] as List<dynamic>? ?? [];

    return _buildActionCardShell(
      context: context,
      icon: Icons.shopping_cart_rounded,
      iconColor: AppTheme.accentColor,
      title: 'Create Purchase Order',
      children: [
        Text('Vendor: $vendor',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
        if (items.isNotEmpty)
          Text('Items: ${items.length}',
              style: TextStyle(
                  color: AppTheme.textSec(context), fontSize: 13)),
        if (!widget.message.isActionExecuted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                // Navigate to PO creation screen
                widget.onSendMessage('Create a purchase order for $vendor');
                setState(() => widget.message.isActionExecuted = true);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create PO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSalesOrderCard(
      BuildContext context, Map<String, dynamic> payload) {
    final customer = payload['customer'] ?? 'Unknown Customer';
    final items = payload['items'] as List<dynamic>? ?? [];

    return _buildActionCardShell(
      context: context,
      icon: Icons.receipt_long_rounded,
      iconColor: AppTheme.violetColor,
      title: 'Create Sales Order',
      children: [
        Text('Customer: $customer',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
        if (items.isNotEmpty)
          Text('Items: ${items.length}',
              style: TextStyle(
                  color: AppTheme.textSec(context), fontSize: 13)),
        if (!widget.message.isActionExecuted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.onSendMessage(
                    'Create a sales order for $customer');
                setState(() => widget.message.isActionExecuted = true);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create SO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.violetColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNavigateCard(
      BuildContext context, Map<String, dynamic> payload) {
    final target = payload['target'] ?? 'unknown';
    final targetLabels = {
      'billing': 'Billing / POS',
      'orders': 'Orders',
      'products': 'Products',
      'audit': 'Audit Log',
      'reports': 'Reports',
    };

    return _buildActionCardShell(
      context: context,
      icon: Icons.open_in_new_rounded,
      iconColor: AppTheme.cyanColor,
      title: 'Navigate',
      children: [
        Text('Go to: ${targetLabels[target] ?? target}',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
        if (!widget.message.isActionExecuted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() => widget.message.isActionExecuted = true);
                // TODO: Implement navigation to target screen
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Go'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReportCard(
      BuildContext context, Map<String, dynamic> payload) {
    final reportType = payload['report_type'] ?? 'General Report';

    return _buildActionCardShell(
      context: context,
      icon: Icons.description_rounded,
      iconColor: AppTheme.indigoColor,
      title: 'Report Generated',
      children: [
        Text('Type: $reportType',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
        if (!widget.message.isActionExecuted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() => widget.message.isActionExecuted = true);
                // TODO: Implement report download
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.indigoColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGenericActionCard(
      BuildContext context, Map<String, dynamic> payload) {
    return _buildActionCardShell(
      context: context,
      icon: Icons.smart_toy_rounded,
      iconColor: AppTheme.primaryColor,
      title: 'AI Action',
      children: [
        Text('Type: ${payload['type'] ?? 'unknown'}',
            style: TextStyle(
                color: AppTheme.textSec(context), fontSize: 14)),
      ],
    );
  }
}
