import 'dart:ui';
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
    _Message("Hi! I'm Nova, your intelligent inventory assistant. How can I help you manage your stock today?", false)
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
    if (predefinedText == null) _controller.clear();
    // Zero-token Interceptor for greetings (Includes Hinglish!)
    final greetings = ['hi', 'hello', 'hey', 'help', 'who are you', 'how are you', 'namaste', 'kaise ho', 'kya haal', 'aur batao'];
    if (greetings.contains(lowerText)) {
      await Future.delayed(const Duration(milliseconds: 600)); // Simulate think time
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message("Hi! I'm Nova, your Inventory AI. Ask me about stock levels or restocking, and I'll keep it brief!", false));
          _isLoading = false;
        });
        _scrollToBottom();
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
              "Sure, let me take you there.",
              false,
              actionPayload: {'type': 'navigate', 'target': target},
            ));
            _isLoading = false;
          });
          _scrollToBottom();
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
    
    // Determine the intent to filter products smartly (Now with Hinglish Support)
    String intentContext = "";
    List<dynamic> relevantProducts = [];
    
    if (lowerText.contains('summary') || lowerText.contains('overview') || lowerText.contains('total') || lowerText.contains('how many') || lowerText.contains('stats') || lowerText.contains('kitna') || lowerText.contains('sab batao') || lowerText.contains('pura stock')) {
      intentContext = "[SYSTEM: User wants an overview. They might speak Hinglish (Hindi in English). Answer naturally. Provide a sharp 1-sentence summary based on these stats: Total Products: $totalItems, Low Stock: $lowStockCount, Out of Stock: $outOfStockCount, Pending Sales: $pendingSales, Pending Purchase Orders: $pendingPurchase]";
    } else if (lowerText.contains('low') || lowerText.contains('restock') || lowerText.contains('out of stock') || lowerText.contains('khatam') || lowerText.contains('kam hai') || lowerText.contains('mangwana')) {
      relevantProducts = provider.lowStockProducts.take(10).toList();
      if (relevantProducts.isEmpty) {
        intentContext = "[SYSTEM: User asked for restocking advice (possibly in Hinglish). Their inventory is perfectly healthy! Congratulate them in 1 sentence.]";
      } else {
        intentContext = "[SYSTEM: Focus on urgent restocking. They might speak Hinglish. Here are the most critical low stock items:]";
      }
    } else if (lowerText.contains('sale') || lowerText.contains('purchase') || lowerText.contains('order') || lowerText.contains('bikri') || lowerText.contains('kharid')) {
       intentContext = "[SYSTEM: User asked about orders (possibly in Hinglish). We currently have $pendingSales pending sales and $pendingPurchase pending purchase orders.]";
    } else {
      relevantProducts = allProducts.where((p) => 
        lowerText.contains(p.name.toLowerCase()) || lowerText.contains(p.barcode.toLowerCase()) || p.categoryName.toLowerCase().contains(lowerText)
      ).take(5).toList();
      
      if (relevantProducts.isEmpty && allProducts.isNotEmpty) {
        intentContext = "[SYSTEM: General query. Answer smartly using these sample products and overall stats (Total: $totalItems, Low: $lowStockCount)]";
        relevantProducts = allProducts.take(5).toList();
      }
    }

    // Map context into an extremely minified string to save max tokens
    final productContext = relevantProducts.isEmpty ? "" : relevantProducts.map((p) => 
      '${p.name}(BC:${p.barcode},Qty:${p.quantity},Min:${p.lowStockThreshold})'
    ).join(' | ');

    final contextText = '$intentContext $productContext'.trim();

    try {
      final response = await RagApiService.askQuestion(
        text,
        context: contextText.isNotEmpty ? contextText : "No inventory data found.",
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(_Message(response.text, false, actionPayload: response.actionPayload));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _messages.add(_Message("Sorry, I couldn't reach the server. Please ensure the backend is running.", false));
          _isLoading = false;
        });
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
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _messages.clear();
                      _messages.add(_Message("Hi! I'm Nova, your intelligent inventory assistant. How can I help you manage your stock today?", false));
                    });
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
                return _ChatBubble(message: message)
                    .animate()
                    .fade(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0, left: 24.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surface(context).withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 2),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryColor, size: 16),
                    ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 1500.ms, color: Colors.white).scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 800.ms).then().scale(begin: const Offset(1.1, 1.1), end: const Offset(0.9, 0.9), duration: 800.ms),
                    const SizedBox(width: 14),
                    const Text(
                      'Analyzing inventory...',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fade(begin: 0.4, end: 1.0, duration: 800.ms),
                  ],
                ),
              ),
            ),
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

  const _ChatBubble({required this.message});

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
