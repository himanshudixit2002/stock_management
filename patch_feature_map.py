import re

with open("lib/config/feature_map.dart", "r") as f:
    content = f.read()

# Add AI Assistant to the top of dailyOps
ai_feature = """    FeatureEntry(
      id: 'aiAssistant',
      label: 'AI Assistant (Bot)',
      subtitle: 'Conversational AI to query stock, sales, and analytics',
      icon: Icons.auto_awesome_rounded,
      route: AppRoutes.home,
      category: FeatureCategory.dailyOps,
      placement: FeaturePlacement.homeSecondary,
      sortOrder: -1,
    ),
"""

start_idx = content.find("    // ---------------- Daily operations")
if start_idx != -1:
    end_idx = content.find("\n", start_idx) + 1
    content = content[:end_idx] + ai_feature + content[end_idx:]

with open("lib/config/feature_map.dart", "w") as f:
    f.write(content)

print("Feature map patched!")
