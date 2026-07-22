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
import '../../widgets/floating_nav_padding.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key});

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _Message {
  final String text;
  final bool isUser;
  final Map<String, dynamic>? actionPayload;
  bool isActionExecuted;

  _Message(this.text, this.isUser, {this.actionPayload, this.isActionExecuted = false});
}

class _RagChatScreenState extends State<RagChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_Message> _messages = [
    _Message("Greetings! I am **Nova**, Chief Supply Chain & Inventory Intelligence Strategist for SmartShelfKart.\n\nHow can I optimize your stock velocity, analyze risk exposure, or synthesize a reorder plan today?", false)
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChatHistory();
    });
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

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _startListening() async {
    await _speechToText.listen(onResult: (result) {
      setState(() {
        _controller.text = result.recognizedWords;
      });
      if (result.finalResult) {
        _stopListening();
      }
    });
    setState(() {
      _isListening = true;
    });
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
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
    // Zero-token Interceptor for greetings (Includes Hinglish!)
    final greetings = ['hi', 'hello', 'hey', 'help', 'who are you', 'how are you', 'namaste', 'kaise ho', 'kya haal', 'aur batao'];
    if (greetings.contains(lowerText)) {
      await Future.delayed(const Duration(milliseconds: 600)); // Simulate think time
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message("Greetings! I am **Nova**, Chief Supply Chain & Inventory Intelligence Strategist. Ask me about stock velocity, risk exposure, or reorder blueprints!", false));
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
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          HapticFeedback.mediumImpact();
          setState(() {
            _messages.add(_Message(
              "🚀 **Executing Neural Route**: Transferring control to **$target** module...",
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

    // Fetch live products to provide as context (use full catalog if available)
    final provider = context.read<ProductProvider>();
    final salesProvider = context.read<SalesOrderProvider>();
    final purchaseProvider = context.read<PurchaseOrderProvider>();
    
    // SMART FETCHING: Ensure Firestore data is fully loaded before calculating stats
    if (!provider.isAnalyticsLoaded) {
      await provider.loadAnalytics();
    }
    
    final allProducts = provider.analyticsProducts;
    
    // Build an ultra-smart, zero-cost summary
    final totalItems = allProducts.length;
    final lowStockCount = provider.lowStockProducts.length;
    final outOfStockCount = allProducts.where((p) => p.isOutOfStock).length;
    final pendingSales = salesProvider.orders.where((o) => o.status != SOStatus.delivered && o.status != SOStatus.cancelled).length;
    final pendingPurchase = purchaseProvider.orders.where((o) => o.status != POStatus.received && o.status != POStatus.cancelled).length;
    
    // Determine the intent to filter products smartly (Now with Hinglish & Strategic Intelligence Support)
    String intentContext = "";
    List<dynamic> relevantProducts = [];
    
    if (lowerText.contains('summary') || lowerText.contains('overview') || lowerText.contains('total') || lowerText.contains('how many') || lowerText.contains('stats') || lowerText.contains('kitna') || lowerText.contains('sab batao') || lowerText.contains('pura stock')) {
      intentContext = "[SYSTEM DIRECTIVE: User requested inventory summary. Deliver an extraordinary strategic briefing with 3 pillars (Velocity snapshot: Total $totalItems, Low $lowStockCount, Out $outOfStockCount; Exposure: $pendingSales pending sales, $pendingPurchase pending POs; Executive Blueprint). Be visionary & crisp!]";
    } else if (lowerText.contains('low') || lowerText.contains('restock') || lowerText.contains('out of stock') || lowerText.contains('khatam') || lowerText.contains('kam hai') || lowerText.contains('mangwana')) {
      relevantProducts = provider.lowStockProducts.take(10).toList();
      if (relevantProducts.isEmpty) {
        intentContext = "[SYSTEM DIRECTIVE: Restock analysis requested. All stock is 100% healthy! Congratulate the user with an executive status confirmation.]";
      } else {
        intentContext = "[SYSTEM DIRECTIVE: Urgent restock advisory. Provide an extraordinary executive reorder blueprint with stockout risk scores for these items:]";
      }
    } else if (lowerText.contains('sale') || lowerText.contains('purchase') || lowerText.contains('order') || lowerText.contains('bikri') || lowerText.contains('kharid')) {
       intentContext = "[SYSTEM DIRECTIVE: Order pipeline analysis. Provide strategic breakdown of $pendingSales pending sales orders and $pendingPurchase pending POs with fulfillment velocity insights.]";
    } else {
      relevantProducts = allProducts.where((p) => 
        lowerText.contains(p.name.toLowerCase()) || lowerText.contains(p.barcode.toLowerCase()) || p.categoryName.toLowerCase().contains(lowerText)
      ).take(5).toList();
      
      if (relevantProducts.isEmpty && allProducts.isNotEmpty) {
        intentContext = "[SYSTEM DIRECTIVE: Executive inventory inquiry. Analyze using strategic context: Total catalog count: $totalItems, Low stock alert count: $lowStockCount. Deliver sharp, actionable guidance.]";
        relevantProducts = allProducts.take(5).toList();
      }
    }

    // Map context into an extremely minified string to save max tokens
    final productContext = relevantProducts.isEmpty ? "" : relevantProducts.map((p) => 
      '${p.name}(BC:${p.barcode},Qty:${p.quantity},Min:${p.lowStockThreshold})'
    ).join(' | ');

    final contextText = '$intentContext $productContext'.trim();

    // Map recent messages to backend format (excluding the last one we just added)
    final historyMessages = _messages
        .take(_messages.length - 1)
        .where((m) => m.text != "Hi! I'm Nova, your intelligent inventory assistant. How can I help you manage your stock today?")
        .toList();
    
    // Take the last 6 messages (3 turns)
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
          _messages.add(_Message(response.text, false, actionPayload: response.actionPayload));
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
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Let HomeScreen's gradient show through
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              title: const Text('Nova AI', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppTheme.bg(context).withValues(alpha: 0.7),
              elevation: 0,
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Clear Chat',
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _messages.clear();
                      _messages.add(_Message("Hi! I'm Nova, your intelligent inventory assistant. How can I help you manage your stock today?", false));
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
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                bottom: 16,
                left: 16,
                right: 16,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _ChatBubble(
                  message: message,
                  onActionExecuted: _saveChatHistory,
                )
                    .animate()
                    .fade(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
              },
            ),
          ),
          if (_isLoading) const _AdvancedThinkingWidget(),
          _buildQuickActions(),
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _QuickActionChip(
            label: "Inventory Summary",
            icon: Icons.pie_chart_rounded,
            onTap: () => _sendMessage("Give me a summary of my inventory"),
          ),
          const SizedBox(width: 10),
          _QuickActionChip(
            label: "Low Stock Items",
            icon: Icons.warning_rounded,
            onTap: () => _sendMessage("What items are low in stock?"),
          ),
          const SizedBox(width: 10),
          _QuickActionChip(
            label: "Restock Advice",
            icon: Icons.shopping_cart_rounded,
            onTap: () => _sendMessage("What should I order next?"),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.8, end: 0, curve: Curves.easeOutQuart);
  }

  Widget _buildInputArea(BuildContext context) {
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
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surface(context).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: AppTheme.textPri(context), fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Ask Nova...',
                          hintStyle: TextStyle(color: AppTheme.textPri(context).withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        icon: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening ? AppTheme.dangerColor : AppTheme.textSec(context),
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
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ]
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: _isLoading ? null : () => _sendMessage(),
                      ),
                    ).animate().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.easeOutBack),
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

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionChip({required this.label, required this.icon, required this.onTap});

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
          )
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 1.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primaryColor),
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

  const _ChatBubble({required this.message, this.onActionExecuted});

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
           // change == 0, ignore
           success = true; 
        }

        if (success) {
          setState(() {
            widget.message.isActionExecuted = true;
          });
          HapticFeedback.heavyImpact();
          if (widget.onActionExecuted != null) {
            widget.onActionExecuted!();
          }
          // Clear backend RAG query cache since stock has updated
          RagApiService.clearCache();
        } else {
          // If update failed, we could show a snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update stock.')));
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
    
    Widget bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        gradient: isUser 
            ? AppTheme.primaryGradient 
            : LinearGradient(
                colors: [AppTheme.surface(context).withValues(alpha: 0.85), AppTheme.bg(context).withValues(alpha: 0.95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: isUser ? null : Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1.5),
        borderRadius: BorderRadius.circular(24).copyWith(
          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(24),
          bottomLeft: isUser ? const Radius.circular(24) : const Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: isUser ? AppTheme.primaryColor.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: isUser 
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
              p: TextStyle(color: AppTheme.textPri(context), fontSize: 15, height: 1.4, letterSpacing: 0.1),
              strong: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w900, fontSize: 15),
              listBullet: const TextStyle(color: AppTheme.primaryColor, fontSize: 15, fontWeight: FontWeight.bold),
              blockSpacing: 8,
              tableBorder: TableBorder.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 1, borderRadius: BorderRadius.circular(8)),
              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tableBody: TextStyle(color: AppTheme.textPri(context), fontSize: 14),
              tableHead: const TextStyle(color: AppTheme.primaryColor, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
    );

    if (widget.message.actionPayload != null && !isUser) {
      final payload = widget.message.actionPayload!;
      final qty = payload['qty_change'] ?? 0;
      final actionDesc = (qty >= 0) ? "Add $qty units" : "Deduct ${qty.abs()} units";
      
      Widget actionCard = Container(
        margin: const EdgeInsets.only(top: 8, bottom: 12, left: 40),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.message.isActionExecuted ? Colors.green.withValues(alpha: 0.3) : AppTheme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.message.isActionExecuted ? Icons.check_circle_rounded : Icons.warning_rounded,
                  color: widget.message.isActionExecuted ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.message.isActionExecuted ? "Action Executed" : "Pending AI Action",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPri(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Task: $actionDesc",
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 14),
            ),
            Text(
              "Barcode: ${payload['barcode']}",
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
            ),
            if (!widget.message.isActionExecuted) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isExecuting ? null : () => _executeAction(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: _isExecuting 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Confirm & Execute"),
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
                  BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
            ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 2000.ms, color: Colors.white.withValues(alpha: 0.8)),
            Flexible(child: bubble),
          ],
        ),
      );
    }
  }
}

class _AdvancedThinkingWidget extends StatefulWidget {
  const _AdvancedThinkingWidget();

  @override
  State<_AdvancedThinkingWidget> createState() => _AdvancedThinkingWidgetState();
}

class _AdvancedThinkingWidgetState extends State<_AdvancedThinkingWidget> {
  int _currentStepIndex = 0;
  bool _isExpanded = false;
  Timer? _timer;

  final List<String> _stages = [
    "⚡ Querying Neural Vector Index & Context Graph...",
    "🔍 Aggregating Product Metrics & Stock Telemetry...",
    "📊 Evaluating Inventory Velocity, Turnover & Risk Exposure...",
    "💡 Synthesizing Extraordinary Executive Blueprint...",
  ];

  final List<String> _reasoningLogs = [
    "• Initialized Gemini 3.5 Deep Reasoning Engine",
    "• Retrieved live stock analytics & transactional context",
    "• Cross-referencing threshold limits & order imbalances",
    "• Applying executive supply-chain decision rules",
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
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
    final currentStage = _stages[_currentStepIndex];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0, left: 16.0, right: 16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withValues(alpha: 0.15),
                AppTheme.surface(context).withValues(alpha: 0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.25),
                blurRadius: 18,
                spreadRadius: 1,
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Animated pulsing radar icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                          child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 16),
                        ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                         .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.15, 1.15), duration: 800.ms),
                        
                        const SizedBox(width: 10),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.5), width: 0.8),
                                    ),
                                    child: const Text(
                                      "DEEP REASONING",
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "[${_currentStepIndex + 1}/${_stages.length}]",
                                    style: TextStyle(
                                      color: AppTheme.textSec(context),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                                child: Text(
                                  currentStage,
                                  key: ValueKey(_currentStepIndex),
                                  style: TextStyle(
                                    color: AppTheme.textPri(context),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Expand / collapse trigger button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isExpanded = !_isExpanded;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.surface(context).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1),
                            ),
                            child: Icon(
                              _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
                              color: AppTheme.primaryColor,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Progress bar indicator
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentStepIndex + 1) / _stages.length,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                        minHeight: 3,
                      ),
                    ),

                    // Expandable detailed thought trace drawer
                    if (_isExpanded) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(_reasoningLogs.length, (idx) {
                            final isDone = idx <= _currentStepIndex;
                            final isCurrent = idx == _currentStepIndex;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Icon(
                                    isDone ? Icons.check_circle_outlined : Icons.circle_outlined,
                                    size: 12,
                                    color: isCurrent 
                                        ? AppTheme.primaryColor 
                                        : (isDone ? Colors.green : Colors.grey.withValues(alpha: 0.5)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _reasoningLogs[idx],
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: isCurrent 
                                            ? AppTheme.primaryColor 
                                            : (isDone ? AppTheme.textPri(context) : AppTheme.textSec(context).withValues(alpha: 0.6)),
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1)),
      ),
    );
  }
}
