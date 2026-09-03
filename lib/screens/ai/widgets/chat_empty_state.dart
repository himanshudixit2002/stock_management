import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../widgets/animations.dart';

/// One thing the assistant can do, offered before the conversation starts.
class ChatSuggestion {
  const ChatSuggestion(this.icon, this.title, this.prompt);
  final IconData icon;
  final String title;

  /// What is actually sent — kept separate from [title] so the card can read
  /// naturally while the query stays precise.
  final String prompt;
}

const chatSuggestions = <ChatSuggestion>[
  ChatSuggestion(
    Icons.inventory_2_rounded,
    'Stock snapshot',
    'Give me a stock snapshot',
  ),
  ChatSuggestion(
    Icons.trending_down_rounded,
    "What's running low?",
    'Which products are running low on stock?',
  ),
  ChatSuggestion(
    Icons.shopping_cart_checkout_rounded,
    'What should I reorder?',
    'What should I reorder, and how much?',
  ),
  ChatSuggestion(
    Icons.query_stats_rounded,
    'Which items sell fastest?',
    'Which products are my best sellers?',
  ),
  // The assistant can change many products at once, and nobody discovers that
  // by guessing — every change it previews first, so trying it is safe.
  ChatSuggestion(
    Icons.layers_rounded,
    'Top up everything low',
    'Restock all low stock items back to their minimum',
  ),
  ChatSuggestion(
    Icons.tune_rounded,
    'How is my inventory set up?',
    'How is my inventory configured?',
  ),
];

/// The greeting shown on an empty conversation.
///
/// Replaces a greeting that was seeded into the message list as a markdown
/// **table** of commands — so the very first thing a new user saw was a table
/// rendered through the table container. Suggestions live here rather than in a
/// permanent chip strip above the composer, so they disappear once there is a
/// conversation to read.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaleFadeIn(
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGrad(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.onGradient,
                  size: 23,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLG),
            FadeSlideIn(
              child: Text(
                'Ask about your inventory',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            FadeSlideIn(
              index: 1,
              child: Text(
                'Answers come from your live stock and transaction history, so '
                'the numbers match your Reports.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXL),
            for (var i = 0; i < chatSuggestions.length; i++)
              FadeSlideIn(
                index: i + 2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
                  child: Material(
                    color: AppTheme.surface(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    child: InkWell(
                      onTap: () => onPick(chatSuggestions[i].prompt),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingLG,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMD),
                          border:
                              Border.all(color: AppTheme.dividerC(context)),
                        ),
                        child: Row(
                          children: [
                            Icon(chatSuggestions[i].icon,
                                size: 18, color: accent),
                            const SizedBox(width: AppTheme.spacingMD),
                            Expanded(
                              child: Text(
                                chatSuggestions[i].title,
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 15,
                              color: AppTheme.iconMute(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
