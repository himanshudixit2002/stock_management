import re

with open("lib/screens/settings/plan_features_screen.dart", "r") as f:
    content = f.read()

new_card = """    return Container(
      decoration: AppTheme.cardDeco(context).copyWith(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.label}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onGradient,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.definition.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onGradient.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (plan.definition.nominalPrice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, right: 8),
                    child: Text(
                      '${AppTheme.currencySymbol}${plan.definition.nominalPrice}/mo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.onGradient.withValues(alpha: 0.6),
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppTheme.onGradient.withValues(alpha: 0.6),
                        decorationThickness: 2.0,
                      ),
                    ),
                  ),
                if (plan.definition.promotionalPrice == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [AppTheme.coloredShadow(Colors.black.withValues(alpha: 0.1))],
                    ),
                    child: const Text(
                      'FREE FOREVER',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                else if (plan.definition.promotionalPrice != null)
                   Text(
                      '${AppTheme.currencySymbol}${plan.definition.promotionalPrice}/mo',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.onGradient,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Features unlocked',
                    value: '$available of $total',
                    color: AppTheme.onGradient,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Active since',
                    value: plan.startedAt != null
                        ? AppDates.day.format(plan.startedAt!)
                        : '—',
                    color: AppTheme.onGradient,
                  ),
                ),
              ],
            ),
            if (plan.definition.limits.isEmpty) ...[
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.all_inclusive_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No limits on products, orders, invoices, users, or AI capabilities.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.onGradient,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              ...plan.definition.limits.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.onGradient.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${e.value}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onGradient,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (plan.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(plan.note, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.onGradient.withValues(alpha: 0.8))),
            ],
          ],
        ),
      ),
    );"""

# Replace the build method of _PlanCard
start_idx = content.find("    return GlassPanel(")
end_idx = content.find("  }\n}\n\nclass _MiniStat")

content = content[:start_idx] + new_card + "\n" + content[end_idx:]

with open("lib/screens/settings/plan_features_screen.dart", "w") as f:
    f.write(content)

print("Card patched!")
