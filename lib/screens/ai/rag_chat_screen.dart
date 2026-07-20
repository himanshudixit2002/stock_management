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

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening() async {
    await _speechToText.listen(onResult: (result) {
      setState(() => _controller.text = result.recognizedWords);
      if (result.finalResult) {
        _stopListening();
        Future.delayed(const Duration(seconds: 1), () {
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
          '[SYSTEM: User wants an overview. They might speak Hinglish. Provide a sharp summary. Total Products: $totalItems, Low Stock: $lowStockCount, Out of Stock: $outOfStockCount, Pending Sales: $pendingSales, Pending POs: $pendingPurchase]';
    } else if (lowerText.contains('low') ||
        lowerText.contains('restock') ||
        lowerText.contains('out of stock') ||
        lowerText.contains('khatam') ||
        lowerText.contains('kam hai') ||
        lowerText.contains('mangwana')) {
      relevantProducts = provider.lowStockProducts.take(10).toList();
      if (relevantProducts.isEmpty) {
        intentContext = '[SYSTEM: Inventory is healthy! Congratulate them.]';
      } else {
        intentContext = '[SYSTEM: Focus on urgent restocking. Critical low stock items:]';
      }
    } else if (lowerText.contains('sale') ||
        lowerText.contains('purchase') ||
        lowerText.contains('order') ||
        lowerText.contains('bikri') ||
        lowerText.contains('kharid')) {
      intentContext =
          '[SYSTEM: Orders query. Pending sales: $pendingSales, Pending POs: $pendingPurchase.]';
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
            '[SYSTEM: General query. Total: $totalItems, Low: $lowStockCount]';
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

    // Cancel any previous request and start fresh
    chatProvider.cancelActiveRequest();
    chatProvider.addUserMessage(text);
    chatProvider.setLoading(true);
    if (predefinedText == null) _controller.clear();
    _scrollToBottom();

    // Grab a request ID to check if this request is still active later
    final requestId = chatProvider.getRequestId();

    // Zero-token interceptor for greetings
    final greetings = [
      'hi', 'hello', 'hey', 'help', 'who are you', 'how are you',
      'namaste', 'kaise ho', 'kya haal', 'aur batao',
    ];
    if (greetings.contains(lowerText)) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && chatProvider.isRequestActive(requestId)) {
        HapticFeedback.mediumImpact();
        chatProvider.setLoading(false);
        chatProvider.addBotMessage(ChatMessage(
          text: "Hi! I'm Nova, your Inventory AI. Ask me about stock levels, orders, or analytics!",
          isUser: false,
          intent: 'GREETING',
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
      if (lowerText.contains('billing') || lowerText.contains('pos') || lowerText.contains('sale')) {
        target = 'billing';
      } else if (lowerText.contains('order')) {
        target = 'orders';
      } else if (lowerText.contains('product') || lowerText.contains('item')) {
        target = 'products';
      } else if (lowerText.contains('audit') || lowerText.contains('stock take')) {
        target = 'audit';
      } else if (lowerText.contains('report')) {
        target = 'reports';
      }

      if (target != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && chatProvider.isRequestActive(requestId)) {
          HapticFeedback.mediumImpact();
          chatProvider.setLoading(false);
          chatProvider.addBotMessage(ChatMessage(
            text: 'Sure, navigating you there.',
            isUser: false,
            intent: 'NAVIGATION',
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

      // Check if request was cancelled while building context
      if (!chatProvider.isRequestActive(requestId)) return;

      final response = await RagApiService.askQuestion(
        text,
        context: contextText.isNotEmpty ? contextText : null,
        chatHistory: chatProvider.getChatHistory(),
      );

      // Check if this request is still the active one
      if (!mounted || !chatProvider.isRequestActive(requestId)) return;

      // Empty text means the request was cancelled
      if (response.text.isEmpty) return;

      HapticFeedback.mediumImpact();
      chatProvider.setLoading(false);
      chatProvider.addBotMessage(ChatMessage(
        text: response.text,
        isUser: false,
        actionPayload: response.actionPayload,
        intent: response.intent,
        latencyMs: response.latencyMs,
        cached: response.cached,
      ));
      _scrollToBottom();
    } catch (e) {
      if (!mounted || !chatProvider.isRequestActive(requestId)) return;
      HapticFeedback.heavyImpact();
      chatProvider.setLoading(false);
      chatProvider.addBotMessage(ChatMessage(
        text: "Something went wrong. Please try again.",
        isUser: false,
      ));
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
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
          resizeToAvoidBottomInset: true,
          drawer: _buildSessionDrawer(context, chatProvider),
          appBar: _buildAppBar(context, chatProvider),
          body: Column(
            children: [
              Expanded(
                child: chatProvider.messages.isEmpty
                    ? _buildEmptyState(context)
                    : _buildMessageList(context, chatProvider),
              ),
              if (chatProvider.isLoading) _buildLoadingIndicator(context),
              _buildSmartSuggestions(context, chatProvider),
              _buildInputArea(context, chatProvider),
            ],
          ),
        );
      },
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, ChatProvider chatProvider) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                const Text('Nova', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            backgroundColor: AppTheme.bg(context).withValues(alpha: 0.8),
            elevation: 0,
            centerTitle: true,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.history_rounded, size: 22),
                tooltip: 'History',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            actions: [
              if (chatProvider.isLoading)
                IconButton(
                  icon: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 22),
                  tooltip: 'Stop',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    chatProvider.cancelActiveRequest();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 22),
                tooltip: 'New Chat',
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

  Widget _buildSessionDrawer(BuildContext context, ChatProvider chatProvider) {
    return Drawer(
      backgroundColor: AppTheme.bg(context),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: AppTheme.heroGradient),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nova AI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Chat History', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    onPressed: () {
                      chatProvider.startNewSession();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: chatProvider.sessions.isEmpty
                  ? Center(child: Text('No conversations yet', style: TextStyle(color: AppTheme.textMute(context))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: chatProvider.sessions.length,
                      itemBuilder: (context, index) {
                        final session = chatProvider.sessions[index];
                        final isActive = session.id == chatProvider.currentSession?.id;
                        return Dismissible(
                          key: Key(session.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: AppTheme.dangerColor,
                            child: const Icon(Icons.delete_rounded, color: Colors.white),
                          ),
                          onDismissed: (_) => chatProvider.deleteSession(session.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                            leading: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                              color: isActive ? AppTheme.primaryColor : AppTheme.textMute(context),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 14,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                            subtitle: Text(
                              '${session.messageCount} messages',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMute(context)),
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
      _EmptySuggestion('Inventory\nOverview', Icons.pie_chart_rounded, 'Give me a summary of my inventory'),
      _EmptySuggestion('Low Stock\nItems', Icons.warning_rounded, 'What items are low in stock?'),
      _EmptySuggestion('Pending\nOrders', Icons.receipt_long_rounded, 'Show me pending orders'),
      _EmptySuggestion('Sales\nAnalytics', Icons.trending_up_rounded, 'Show me the sales trend'),
    ];

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 24,
        left: 24,
        right: 24,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 2500.ms, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(height: 20),
              Text(
                "Hi! I'm Nova",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPri(context),
                  letterSpacing: -0.5,
                ),
              ).animate().fade(duration: 400.ms).slideY(begin: 0.1),
              const SizedBox(height: 6),
              Text(
                'Your intelligent inventory assistant',
                style: TextStyle(fontSize: 14, color: AppTheme.textSec(context)),
              ).animate().fade(delay: 150.ms, duration: 400.ms),
              const SizedBox(height: 28),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.8,
                children: suggestions.asMap().entries.map((entry) {
                  return _buildSuggestionCard(context, entry.value, entry.key);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(BuildContext context, _EmptySuggestion s, int index) {
    return GestureDetector(
      onTap: () => _sendMessage(s.prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface(context).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(s.icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.label,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textPri(context)),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fade(delay: (150 + index * 80).ms, duration: 350.ms)
        .slideY(begin: 0.08, end: 0);
  }

  // ── Message List ─────────────────────────────────────────────────────────

  Widget _buildMessageList(BuildContext context, ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
        bottom: 8,
        left: 14,
        right: 14,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return _ChatBubble(
          message: messages[index],
          onSendMessage: _sendMessage,
        );
      },
    );
  }

  // ── Loading Indicator ────────────────────────────────────────────────────

  Widget _buildLoadingIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Thinking...',
              style: TextStyle(
                color: AppTheme.primaryColor.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ).animate().fade(duration: 200.ms);
  }

  // ── Smart Suggestions ────────────────────────────────────────────────────

  Widget _buildSmartSuggestions(BuildContext context, ChatProvider chatProvider) {
    if (chatProvider.isLoading) return const SizedBox.shrink();
    final suggestions = chatProvider.getSmartSuggestions();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final s = suggestions[index];
          return ActionChip(
            avatar: Icon(s.icon, size: 14, color: AppTheme.primaryColor),
            label: Text(s.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            onPressed: () => _sendMessage(s.prompt),
            backgroundColor: AppTheme.surface(context),
            side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }

  // ── Input Area ───────────────────────────────────────────────────────────

  Widget _buildInputArea(BuildContext context, ChatProvider chatProvider) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 8,
        bottom: keyboardOpen ? 8 : floatingNavContentInset(context),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: AppTheme.surface(context).withValues(alpha: 0.85),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: AppTheme.textPri(context), fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Ask Nova...',
                    hintStyle: TextStyle(color: AppTheme.textPri(context).withValues(alpha: 0.4)),
                    filled: false,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              // Voice button
              if (_speechEnabled)
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : AppTheme.textSec(context),
                    size: 20,
                  ),
                  onPressed: () {
                    _speechToText.isNotListening ? _startListening() : _stopListening();
                  },
                ),
              // Send button
              Container(
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                  onPressed: chatProvider.isLoading ? null : () => _sendMessage(),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session expired.')));
        }
        setState(() => _isExecuting = false);
        return;
      }

      try {
        final products = provider.analyticsProducts;
        final product = products.firstWhere((p) => p.barcode == barcode.toString());
        final int change = (qtyChange as num).toInt();

        final Map<String, int> locQty = product.locationQuantities;
        final String targetLocation = locQty.isNotEmpty ? locQty.keys.first : 'Default';

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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Product not found.')));
        }
      } finally {
        if (mounted) setState(() => _isExecuting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUser;
    final ts = widget.message.timestamp;
    final timeStr = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        bottom: 3,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: isUser
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: widget.message.text));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                  );
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isUser ? AppTheme.primaryGradient : null,
              color: isUser ? null : AppTheme.surface(context),
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isUser ? const Radius.circular(4) : null,
                bottomLeft: isUser ? null : const Radius.circular(4),
              ),
              border: isUser ? null : Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isUser)
                  Text(
                    widget.message.text,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4),
                  )
                else
                  MarkdownBody(
                    data: widget.message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: AppTheme.textPri(context), fontSize: 14, height: 1.5),
                      strong: TextStyle(color: AppTheme.textPri(context), fontWeight: FontWeight.w700),
                      listBullet: TextStyle(color: AppTheme.textSec(context)),
                      code: TextStyle(
                        color: AppTheme.primaryColor,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                        fontSize: 13,
                      ),
                    ),
                    selectable: true,
                  ),
                const SizedBox(height: 4),
                // Meta row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: isUser ? Colors.white70 : AppTheme.textMute(context),
                      ),
                    ),
                    if (!isUser && widget.message.latencyMs != null && widget.message.latencyMs! > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(widget.message.latencyMs! / 1000).toStringAsFixed(1)}s',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMute(context)),
                      ),
                    ],
                    if (!isUser && widget.message.cached == true) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.bolt_rounded, size: 12, color: Colors.amber.shade600),
                    ],
                  ],
                ),
                // Action button
                if (!isUser && widget.message.actionPayload != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: widget.message.isActionExecuted
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade400),
                              const SizedBox(width: 6),
                              Text('Done', style: TextStyle(fontSize: 12, color: Colors.green.shade400, fontWeight: FontWeight.w600)),
                            ],
                          )
                        : FilledButton.tonal(
                            onPressed: _isExecuting ? null : () => _executeAction(context),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                            ),
                            child: _isExecuting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.play_arrow_rounded, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getActionLabel(widget.message.actionPayload!),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getActionLabel(Map<String, dynamic> payload) {
    switch (payload['type']) {
      case 'update_stock':
        final qty = payload['qty_change'];
        return qty != null && (qty as num) > 0 ? 'Add Stock' : 'Remove Stock';
      case 'navigate':
        return 'Navigate';
      case 'create_purchase_order':
        return 'Create PO';
      case 'create_sales_order':
        return 'Create SO';
      default:
        return 'Execute';
    }
  }
}
