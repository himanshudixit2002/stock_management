import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../models/sales_order_model.dart';
import '../../models/purchase_order_model.dart';
import '../../services/rag_api_service.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../utils/responsive.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key});

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _Message {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? statsPayload;
  final List<Map<String, dynamic>>? lowStockItemsPayload;
  bool isActionExecuted;

  _Message(
    this.text,
    this.isUser, {
    this.actionPayload,
    this.statsPayload,
    this.lowStockItemsPayload,
    this.isActionExecuted = false,
  });
}

class _RagChatScreenState extends State<RagChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<_Message> _messages = [
    _Message(
      "👋 **Hey buddy! Ask AI is ready!** ⚡\n\n"
      "• 📊 **Stock Snapshot** - Live counts & health\n"
      "• 🔥 **Low Stock Alert** - Fast restock items\n"
      "• 📦 **Smart Action** - Add/deduct inventory", 
      false,
    )
  ];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChatHistory();
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Smoothly scroll to bottom as software keyboard opens
      Future.delayed(const Duration(milliseconds: 150), () {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _saveChatHistory() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final user = authProvider.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final list = _messages.map((m) => jsonEncode({
        'text': m.text,
        'isUser': m.isUser,
        'actionPayload': m.actionPayload,
        'statsPayload': m.statsPayload,
        'lowStockItemsPayload': m.lowStockItemsPayload,
        'isActionExecuted': m.isActionExecuted,
      })).toList();
      
      await prefs.setStringList('chat_history_${user.uid}', list);
    } catch (e) {
      debugPrint("Error saving chat history: $e");
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final user = authProvider.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('chat_history_${user.uid}');
      if (list != null && list.isNotEmpty) {
        setState(() {
          _messages.clear();
          _messages.addAll(list.map((item) {
            final json = jsonDecode(item);
            return _Message(
              json['text'],
              json['isUser'],
              actionPayload: json['actionPayload'] != null 
                  ? Map<String, dynamic>.from(json['actionPayload']) 
                  : null,
              statsPayload: json['statsPayload'] != null
                  ? Map<String, dynamic>.from(json['statsPayload'])
                  : null,
              lowStockItemsPayload: json['lowStockItemsPayload'] != null
                  ? (json['lowStockItemsPayload'] as List)
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList()
                  : null,
              isActionExecuted: json['isActionExecuted'] ?? false,
            );
          }));
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error loading chat history: $e");
    }
  }

  String _baseText = '';
  double _soundLevel = 0.0;

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening() async {
    if (!_speechEnabled) {
      _speechEnabled = await _speechToText.initialize();
      if (!_speechEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone access unavailable.')));
        }
        return;
      }
    }

    _baseText = _controller.text.trim();
    _soundLevel = 0.0;
    setState(() {
      _isListening = true;
    });

    try {
      await _speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          if (recognized.isEmpty) return;

          setState(() {
            if (_baseText.isNotEmpty) {
              _controller.text = "$_baseText $recognized";
            } else {
              _controller.text = recognized;
            }
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });

          if (result.finalResult) {
            _stopListening();
          }
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        ),
        onSoundLevelChange: (level) {
          if (mounted) {
            setState(() {
              _soundLevel = (level / 10.0).clamp(0.0, 1.0);
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _soundLevel = 0.0;
      });
    }
  }

  void _cancelListening() async {
    await _speechToText.cancel();
    if (mounted) {
      setState(() {
        _controller.text = _baseText;
        _isListening = false;
        _soundLevel = 0.0;
      });
    }
  }

  void _sendMessage([String? predefinedText]) async {
    final text = predefinedText ?? _controller.text.trim();
    if (text.isEmpty) return;
    
    final lowerText = text.toLowerCase();
    
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(_Message(text, true));
      _isLoading = true;
    });
    _saveChatHistory();
    
    if (predefinedText == null) _controller.clear();
    
    // Zero-token Interceptor for greetings
    final greetings = ['hi', 'hello', 'hey', 'help', 'who are you', 'how are you', 'namaste', 'kaise ho', 'kya haal', 'aur batao'];
    if (greetings.contains(lowerText)) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message(
            "👋 **Hey buddy! What's cookin'?** ⚡\n\n"
            "• 📊 **Stock Snapshot**: Get instant totals\n"
            "• 🔥 **Low Stock Alert**: Catch items running out\n"
            "• 📦 **Smart Action**: Update quantities fast",
            false,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    // Zero-token Interceptor for navigation
    if (lowerText.contains('open ') || lowerText.contains('go to ') || lowerText.contains('show me ')) {
      String? target;
      if (lowerText.contains('billing') || lowerText.contains('pos') || lowerText.contains('sale')) target = 'billing';
      else if (lowerText.contains('order')) target = 'orders';
      else if (lowerText.contains('product') || lowerText.contains('item')) target = 'products';
      else if (lowerText.contains('audit') || lowerText.contains('stock take')) target = 'audit';
      else if (lowerText.contains('report')) target = 'reports';

      if (target != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          HapticFeedback.mediumImpact();
          setState(() {
            _messages.add(_Message(
              "🚀 **Boom! Teleporting you to $target...**",
              false,
              actionPayload: {'type': 'navigate', 'target': target},
            ));
            _isLoading = false;
          });
          _scrollToBottom();
          _saveChatHistory();
        }
        return;
      }
    }

    // Fetch live products for analytics context
    final provider = context.read<ProductProvider>();
    final salesProvider = context.read<SalesOrderProvider>();
    final purchaseProvider = context.read<PurchaseOrderProvider>();
    
    if (!provider.isAnalyticsLoaded) {
      await provider.loadAnalytics();
    }
    
    final allProducts = provider.analyticsProducts;
    
    final totalItems = allProducts.length;
    final lowStockProducts = provider.lowStockProducts;
    final lowStockCount = lowStockProducts.length;
    final outOfStockCount = allProducts.where((p) => p.isOutOfStock).length;
    final pendingSales = salesProvider.orders.where((o) => o.status != SOStatus.delivered && o.status != SOStatus.cancelled).length;
    final pendingPurchase = purchaseProvider.orders.where((o) => o.status != POStatus.received && o.status != POStatus.cancelled).length;

    final statsMap = {
      'total': totalItems,
      'low': lowStockCount,
      'out': outOfStockCount,
      'pending_so': pendingSales,
      'pending_po': pendingPurchase,
    };
    
    // Check if user requested summary or low stock alerts locally for instantaneous human response with visual widgets
    if (lowerText.contains('summary') || lowerText.contains('overview') || lowerText.contains('total') || lowerText.contains('stats') || lowerText.contains('kitna') || lowerText.contains('sab batao') || lowerText.contains('pura stock')) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message(
            "⚡ **Live Inventory Pulse:**\n\n"
            "• 📦 **Catalog Items**: $totalItems active products\n"
            "• 🔥 **Low Stock Alerts**: $lowStockCount item(s) running low\n"
            "• ⏳ **Pending Orders**: ${pendingSales + pendingPurchase} order(s) in pipeline",
            false,
            statsPayload: statsMap,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    if (lowerText.contains('low') || lowerText.contains('restock') || lowerText.contains('out of stock') || lowerText.contains('khatam') || lowerText.contains('kam hai') || lowerText.contains('mangwana')) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        HapticFeedback.mediumImpact();
        final lowItemsList = lowStockProducts.take(8).map((p) => {
          'name': p.name,
          'quantity': p.quantity,
          'lowStockThreshold': p.lowStockThreshold,
          'barcode': p.barcode,
          'categoryName': p.categoryName,
        }).toList();

        setState(() {
          _messages.add(_Message(
            lowItemsList.isEmpty 
                ? "🎉 **Woohoo! All stock levels are super healthy!**" 
                : "🔥 **${lowItemsList.length} Item(s) Need Restocking!**\n• Tap any card below to restock in 1 click:",
            false,
            statsPayload: statsMap,
            lowStockItemsPayload: lowItemsList,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    // Determine context for backend RAG
    String intentContext = "[SYSTEM DIRECTIVE: STRICTLY NO PARAGRAPHS! Format answer in 2-3 short, playful, bulleted points (•). Data: Total $totalItems, Low $lowStockCount, Out $outOfStockCount, Pending SO $pendingSales, Pending PO $pendingPurchase]";
    List<dynamic> relevantProducts = allProducts.where((p) => 
      lowerText.contains(p.name.toLowerCase()) || lowerText.contains(p.barcode.toLowerCase()) || p.categoryName.toLowerCase().contains(lowerText)
    ).take(5).toList();

    final productContext = relevantProducts.isEmpty ? "" : relevantProducts.map((p) => 
      '${p.name}(BC:${p.barcode},Qty:${p.quantity},Min:${p.lowStockThreshold})'
    ).join(' | ');

    final contextText = '$intentContext $productContext'.trim();

    final historyMessages = _messages
        .take(_messages.length - 1)
        .where((m) => !m.text.startsWith("Hey! I'm **Ask AI**") && !m.text.startsWith("Greetings!"))
        .toList();
    
    final recentHistory = historyMessages.length > 6 
        ? historyMessages.sublist(historyMessages.length - 6) 
        : historyMessages;
        
    final historyPayload = recentHistory.map((m) => {
      'role': m.isUser ? 'user' : 'model',
      'content': m.text,
    }).toList();

    try {
      final response = await RagApiService.askQuestion(
        text,
        context: contextText.isNotEmpty ? contextText : "No inventory data found.",
        history: historyPayload,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message(
            response.text, 
            false, 
            actionPayload: response.actionPayload,
            statsPayload: response.statsPayload ?? statsMap,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        _saveChatHistory();
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _messages.add(_Message("Sorry, I couldn't reach the server. Please ensure the backend is running.", false));
          _isLoading = false;
        });
        _saveChatHistory();
      }
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true, // Key for soft keyboard synchronization
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              leading: const BackButton(),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text('Ask AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.textPri(context))),
                ],
              ),
              backgroundColor: AppTheme.bg(context).withValues(alpha: 0.6),
              elevation: 0,
              centerTitle: true,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppTheme.primaryColor.withValues(alpha: 0.2),
                        Colors.transparent,
                      ]
                    )
                  )
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  tooltip: 'Clear Chat',
                  color: AppTheme.textSec(context),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _messages.clear();
                      _messages.add(_Message("Hey! I'm **Ask AI**, your smart inventory assistant. Ask me anything about your stock, low items, or pending orders!", false));
                    });
                    await _saveChatHistory();
                    await RagApiService.clearCache();
                  },
                )
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(
                      top: kToolbarHeight + 12,
                      bottom: 12,
                      left: 12,
                      right: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _ChatBubble(
                        message: message,
                        onActionExecuted: _saveChatHistory,
                        onQuickPrompt: (prompt) => _sendMessage(prompt),
                      )
                          .animate()
                          .fade(duration: 300.ms)
                          .slideY(begin: 0.08, end: 0, curve: Curves.easeOutQuad);
                    },
                  ),
                ),
              ),
              if (_isLoading) const _CompactThinkingWidget(),
              if (_isListening)
                _LiveVoiceVisualizerWidget(
                  soundLevel: _soundLevel,
                  onDone: _stopListening,
                  onCancel: _cancelListening,
                ),
              _buildQuickActions(),
              _buildInputArea(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _QuickActionChip(
            label: "⚡ Stock Snapshot",
            icon: Icons.bolt_rounded,
            onTap: () => _sendMessage("Give me a summary of my inventory"),
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            label: "🔥 Low Stock Alert",
            icon: Icons.local_fire_department_rounded,
            onTap: () => _sendMessage("What items are low in stock?"),
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            label: "📦 Smart Restock",
            icon: Icons.inventory_2_rounded,
            onTap: () => _sendMessage("What should I order next?"),
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            label: "🎯 Pending Orders",
            icon: Icons.track_changes_rounded,
            onTap: () => _sendMessage("Show me pending sales orders"),
          ),
          const SizedBox(width: 8),
          _QuickActionChip(
            label: "💡 Quick Tip",
            icon: Icons.lightbulb_outline_rounded,
            onTap: () => _sendMessage("Give me a quick inventory tip"),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.4, end: 0, curve: Curves.easeOutQuart);
  }

  Widget _buildInputArea(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = bottomInset > 0;
    
    // On the AI screen, there is no bottom nav bar.
    // When typing (keyboard open), position the bar JUST ABOVE the keyboard with a sleek 6px gap.
    // When idle (keyboard closed), utilize the very bottom edge with safe area padding.
    final double safeBottom = MediaQuery.of(context).padding.bottom;
    final double bottomPadding = keyboardOpen 
        ? 6.0 
        : (safeBottom > 0 ? safeBottom + 4.0 : 8.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: bottomPadding,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surface(context).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: TextStyle(color: AppTheme.textPri(context), fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Message Ask AI...',
                        hintStyle: TextStyle(color: AppTheme.textPri(context).withValues(alpha: 0.45), fontSize: 15),
                        filled: true,
                        fillColor: Colors.transparent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: _isListening ? AppTheme.dangerColor.withValues(alpha: 0.15) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 20,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _isListening ? AppTheme.dangerColor : AppTheme.textSec(context).withValues(alpha: 0.7),
                      ),
                      onPressed: () async {
                        if (!_speechEnabled) {
                          _speechEnabled = await _speechToText.initialize();
                          if (!_speechEnabled) {
                             if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone not available.')));
                             }
                             return;
                          }
                        }
                        _speechToText.isNotListening ? _startListening() : _stopListening();
                      },
                    ),
                  ).animate(target: _isListening ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15)),
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        )
                      ]
                    ),
                    child: IconButton(
                      iconSize: 18,
                      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                      onPressed: _isLoading ? null : () => _sendMessage(),
                    ),
                  ).animate().scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), curve: Curves.easeOutBack),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: AppTheme.surface(context).withValues(alpha: 0.85),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25), width: 1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: AppTheme.primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.primaryColor),
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

class _ChatBubble extends StatefulWidget {
  final _Message message;
  final VoidCallback? onActionExecuted;
  final Function(String)? onQuickPrompt;

  const _ChatBubble({
    required this.message, 
    this.onActionExecuted,
    this.onQuickPrompt,
  });

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
      
      final products = provider.analyticsProducts;
      
      if (user == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Cannot update stock.')));
        setState(() => _isExecuting = false);
        return;
      }
      
      try {
        final product = products.firstWhere((p) => p.barcode == barcode.toString());
        final int change = (qtyChange as num).toInt();
        
        final Map<String, int> locQty = product.locationQuantities;
        final String targetLocation = locQty.isNotEmpty ? locQty.keys.first : 'Default';

        bool success = false;
        final reason = 'AI Assistant Action';
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

        final scaffoldMessenger = ScaffoldMessenger.of(context);
        if (success) {
          setState(() {
            widget.message.isActionExecuted = true;
          });
          HapticFeedback.heavyImpact();
          if (widget.onActionExecuted != null) {
            widget.onActionExecuted!();
          }
          RagApiService.clearCache();
        } else {
          if (mounted) {
            scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Failed to update stock.')));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product not found in current inventory.')));
        }
      } finally {
        if (mounted) {
          setState(() => _isExecuting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUser;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.82;

    Widget bubbleContent = SelectionArea(
      child: MarkdownBody(
        data: widget.message.text,
        selectable: false,
        shrinkWrap: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: AppTheme.textPri(context), fontSize: 13.5, height: 1.35, letterSpacing: 0.1),
          h1: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 15),
          h2: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 14.5),
          h3: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700, fontSize: 14),
          strong: TextStyle(color: AppTheme.textPri(context), fontWeight: FontWeight.w700, fontSize: 13.5),
          em: TextStyle(color: AppTheme.textPri(context), fontStyle: FontStyle.italic, fontSize: 13.5),
          listBullet: const TextStyle(color: AppTheme.primaryColor, fontSize: 13.5, fontWeight: FontWeight.bold),
          blockSpacing: 4,
          tableBorder: TableBorder(
            horizontalInside: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.1), width: 1),
            bottom: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1),
            top: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1),
          ),
          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          tableBody: TextStyle(color: AppTheme.textPri(context).withValues(alpha: 0.9), fontSize: 12.5, height: 1.25),
          tableHead: const TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.w700),
          tableColumnWidth: const FlexColumnWidth(),
        ),
      ),
    );

    Widget bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      decoration: BoxDecoration(
        gradient: isUser 
            ? AppTheme.primaryGradient 
            : LinearGradient(
                colors: [AppTheme.surface(context).withValues(alpha: 0.95), AppTheme.bg(context)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: isUser ? null : Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.12), width: 1),
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: isUser ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: isUser 
        ? Text(
            widget.message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              bubbleContent,
              if (widget.message.statsPayload != null) ...[
                const SizedBox(height: 6),
                _VisualStatsHeader(stats: widget.message.statsPayload!),
              ],
              if (widget.message.lowStockItemsPayload != null && widget.message.lowStockItemsPayload!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _VisualLowStockCards(
                  items: widget.message.lowStockItemsPayload!,
                  onRestockTap: (item) {
                    if (widget.onQuickPrompt != null) {
                      widget.onQuickPrompt!("Add 10 units of ${item['name']} (Barcode: ${item['barcode']})");
                    }
                  },
                ),
              ],
            ],
          ),
    );

    if (widget.message.actionPayload != null && !isUser) {
      final payload = widget.message.actionPayload!;
      final qty = payload['qty_change'] ?? 0;
      final actionDesc = (qty >= 0) ? "Add $qty units" : "Deduct ${qty.abs()} units";
      
      Widget actionCard = Container(
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        decoration: BoxDecoration(
          color: AppTheme.surface(context).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.message.isActionExecuted ? Colors.green.withValues(alpha: 0.4) : AppTheme.primaryColor.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.message.isActionExecuted ? Icons.check_circle_rounded : Icons.flash_on_rounded,
                  color: widget.message.isActionExecuted ? Colors.green : AppTheme.primaryColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.message.isActionExecuted ? "Action Executed" : "Pending AI Action",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPri(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Task: $actionDesc",
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 12.5),
            ),
            Text(
              "Barcode: ${payload['barcode']}",
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
            ),
            if (!widget.message.isActionExecuted) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isExecuting ? null : () => _executeAction(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                  ),
                  child: _isExecuting 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Confirm & Execute", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
              )
            ]
          ],
        ),
      );
      
      bubble = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bubble, actionCard],
      );
    }

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 36),
          child: bubble,
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(right: 12, top: 3, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8, top: 3),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
            ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 2500.ms, color: Colors.white.withValues(alpha: 0.8)),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: bubble,
              ),
            ),
          ],
        ),
      );
    }
  }
}

// Visual Metric Dashboard Header
class _VisualStatsHeader extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _VisualStatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    final int total = stats['total'] ?? 0;
    final int low = stats['low'] ?? 0;
    final int out = stats['out'] ?? 0;
    final int pending = (stats['pending_so'] ?? 0) + (stats['pending_po'] ?? 0);

    final healthy = (total - low - out).clamp(0, total);
    final healthyPct = total > 0 ? (healthy / total) : 1.0;
    final lowPct = total > 0 ? (low / total) : 0.0;
    final outPct = total > 0 ? (out / total) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 14, color: AppTheme.primaryColor),
              const SizedBox(width: 5),
              Text(
                "Inventory Health Meter",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Multi-segment progress bar visualization
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  if (healthyPct > 0)
                    Expanded(
                      flex: (healthyPct * 100).toInt().clamp(1, 100),
                      child: Container(color: Colors.green),
                    ),
                  if (lowPct > 0)
                    Expanded(
                      flex: (lowPct * 100).toInt().clamp(1, 100),
                      child: Container(color: Colors.amber),
                    ),
                  if (outPct > 0)
                    Expanded(
                      flex: (outPct * 100).toInt().clamp(1, 100),
                      child: Container(color: AppTheme.dangerColor),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Metric Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetricChip(label: "Catalog", value: "$total", color: AppTheme.primaryColor, icon: Icons.inventory_2_outlined),
              _MetricChip(label: "Low Stock", value: "$low", color: Colors.amber.shade700, icon: Icons.warning_amber_rounded),
              _MetricChip(label: "Out Stock", value: "$out", color: AppTheme.dangerColor, icon: Icons.remove_shopping_cart_outlined),
              _MetricChip(label: "Pending", value: "$pending", color: Colors.blue, icon: Icons.pending_actions_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(fontSize: 9.5, color: AppTheme.textSec(context), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// Low Stock Item Cards Visualization Widget
class _VisualLowStockCards extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onRestockTap;

  const _VisualLowStockCards({
    required this.items,
    required this.onRestockTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayItems = items.take(3).toList();
    final int extraCount = items.length - displayItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayItems.map((item) {
          final int qty = (item['quantity'] ?? 0) as int;
          final int minThreshold = (item['lowStockThreshold'] ?? 10) as int;
          final double ratio = minThreshold > 0 ? (qty / minThreshold).clamp(0.0, 1.0) : 0.0;
          final Color statusColor = qty == 0 ? AppTheme.dangerColor : Colors.amber.shade700;

          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surface(context).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item['name'] ?? 'Item',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: AppTheme.textPri(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "$qty / $minThreshold",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "BC: ${item['barcode'] ?? 'N/A'}",
                      style: TextStyle(fontSize: 10, color: AppTheme.textSec(context)),
                    ),
                    InkWell(
                      onTap: () => onRestockTap(item),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              "Restock",
                              style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (extraCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              "+ $extraCount more items low in stock...",
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textSec(context)),
            ),
          ),
      ],
    );
  }
}

class _CompactThinkingWidget extends StatefulWidget {
  const _CompactThinkingWidget();

  @override
  State<_CompactThinkingWidget> createState() => _CompactThinkingWidgetState();
}

class _CompactThinkingWidgetState extends State<_CompactThinkingWidget> {
  int _currentStepIndex = 0;
  bool _isExpanded = false;
  Timer? _timer;

  final List<String> _stages = [
    "Ask AI is thinking...",
    "Checking inventory...",
    "Analyzing data...",
    "Generating response...",
  ];

  final List<String> _reasoningLogs = [
    "• Initializing...",
    "• Scanning...",
    "• Evaluating...",
    "• Processing...",
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (mounted) {
        setState(() {
          if (_currentStepIndex < _stages.length - 1) {
            _currentStepIndex++;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isExpanded = !_isExpanded);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surface(context).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: 0,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryColor, size: 14)
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.15, 1.15), duration: 700.ms),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _stages[_currentStepIndex],
                          key: ValueKey(_currentStepIndex),
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.primaryColor.withValues(alpha: 0.7),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                decoration: BoxDecoration(
                  color: AppTheme.bg(context).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_reasoningLogs.length, (idx) {
                    final isDone = idx <= _currentStepIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Icon(
                            isDone ? Icons.check_circle_outlined : Icons.circle_outlined,
                            size: 11,
                            color: isDone ? AppTheme.primaryColor : Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _reasoningLogs[idx],
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDone 
                                    ? AppTheme.textPri(context).withValues(alpha: 0.9) 
                                    : AppTheme.textSec(context).withValues(alpha: 0.5),
                                fontWeight: isDone ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ).animate().fadeIn(duration: 150.ms).slideY(begin: -0.1, end: 0),
            ]
          ],
        ),
      ),
    );
  }
}

class _LiveVoiceVisualizerWidget extends StatelessWidget {
  final double soundLevel;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const _LiveVoiceVisualizerWidget({
    required this.soundLevel,
    required this.onDone,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.dangerColor.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 0,
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.dangerColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: AppTheme.dangerColor, size: 18),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(0.9, 0.9), end: const Offset(1.15, 1.15), duration: 600.ms),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "Listening...",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.dangerColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SoundWaveBar(level: soundLevel, heightFactor: 0.4),
                    _SoundWaveBar(level: soundLevel, heightFactor: 0.9),
                    _SoundWaveBar(level: soundLevel, heightFactor: 0.6),
                    _SoundWaveBar(level: soundLevel, heightFactor: 1.0),
                    _SoundWaveBar(level: soundLevel, heightFactor: 0.7),
                    _SoundWaveBar(level: soundLevel, heightFactor: 0.5),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Speak clearly into microphone",
                  style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
            tooltip: "Cancel Voice",
            onPressed: onCancel,
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_rounded, size: 22, color: Colors.green),
            tooltip: "Done",
            onPressed: onDone,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2, end: 0);
  }
}

class _SoundWaveBar extends StatelessWidget {
  final double level;
  final double heightFactor;

  const _SoundWaveBar({required this.level, required this.heightFactor});

  @override
  Widget build(BuildContext context) {
    final height = (8.0 + (level * 16.0 * heightFactor)).clamp(6.0, 24.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 3.5,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.dangerColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
