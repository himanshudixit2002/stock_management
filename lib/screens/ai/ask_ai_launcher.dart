import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/deferred_screen_loader.dart';
import 'rag_chat_screen.dart' deferred as rag_chat;

/// Opens the AI assistant.
///
/// The chat screen carries `speech_to_text` and `flutter_markdown`, and it was
/// reached through `RagChatScreen.open` — a static on the screen itself, so
/// every caller (the Home FAB, the insights card, the forecast tab) imported
/// the whole thing eagerly and dragged both packages into the initial bundle.
/// Routing every entry point through this launcher keeps them deferred.
Future<void> openAskAi(BuildContext context) {
  HapticFeedback.lightImpact();
  return Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          DeferredScreenLoader(
            future: rag_chat.loadLibrary(),
            builder: (_) => rag_chat.RagChatScreen(),
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
            child: child,
          ),
        );
      },
    ),
  );
}
