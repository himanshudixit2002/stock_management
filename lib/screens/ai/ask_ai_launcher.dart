import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/deferred_screen_loader.dart';
import 'ai_chat_screen.dart' deferred as ai_chat;

/// Opens the AI assistant.
///
/// The chat screen carries `flutter_markdown`, and it used to also be reachable
/// through `RagChatScreen.open` — a static on the screen itself, so every caller
/// (the Home FAB, the insights card, the forecast tab) imported the whole thing
/// eagerly and dragged the package into the initial bundle. That static is gone;
/// every entry point comes through here, which keeps the screen deferred.
Future<void> openAskAi(BuildContext context) {
  HapticFeedback.lightImpact();
  return Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          DeferredScreenLoader(
            future: ai_chat.loadLibrary(),
            builder: (_) => ai_chat.AiChatScreen(),
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
