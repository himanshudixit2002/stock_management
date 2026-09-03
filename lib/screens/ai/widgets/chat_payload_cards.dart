import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';

/// The structured attachments an answer can carry, rebuilt on the type scale
/// and the theme-aware colour helpers. The originals hardcoded every font size
/// (12 and 12.5 throughout) and used the const `AppTheme.primaryColor`, which is
/// the light-mode teal and sat at poor contrast on the dark ground.

/// The `[STATS:{…}]` payload: a health bar plus the four headline counts.
class ChatStatsCard extends StatelessWidget {
  const ChatStatsCard({super.key, required this.stats});

  final Map<String, dynamic> stats;

  int _int(String key) {
    final v = stats[key];
    return v is num ? v.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final total = _int('total');
    final low = _int('low');
    final out = _int('out');
    final pending = _int('pending_so') + _int('pending_po');
    final healthy = (total - low - out).clamp(0, total);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inventory health', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spacingMD),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    if (healthy > 0)
                      Expanded(
                        flex: healthy,
                        child: ColoredBox(color: AppTheme.success(context)),
                      ),
                    if (low > 0)
                      Expanded(
                        flex: low,
                        child: ColoredBox(color: AppTheme.warning(context)),
                      ),
                    if (out > 0)
                      Expanded(
                        flex: out,
                        child: ColoredBox(color: AppTheme.danger(context)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppTheme.spacingLG),
          // Wrap, not a Row of Expanded: four labelled figures in one row
          // ellipsised "Pending" on a narrow phone even before text scaling.
          Wrap(
            spacing: AppTheme.spacingXL,
            runSpacing: AppTheme.spacingMD,
            children: [
              _Stat('Catalog', total, AppTheme.primary(context)),
              _Stat('Low', low, AppTheme.warning(context)),
              _Stat('Out', out, AppTheme.danger(context)),
              _Stat('Pending', pending, AppTheme.info(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// The rows behind a list answer — low stock, a reorder plan, dead stock.
///
/// Replaces a card that only ever handled low stock and was never rendered at
/// all: nothing in the response carried the items, so the widget was dead code
/// while answers arrived as a wall of markdown table.
class ChatItemListCard extends StatefulWidget {
  const ChatItemListCard({super.key, required this.items, this.kind});

  final List<Map<String, dynamic>> items;

  /// The backend's `response_kind`, which says what the rows mean.
  final String? kind;

  @override
  State<ChatItemListCard> createState() => _ChatItemListCardState();
}

class _ChatItemListCardState extends State<ChatItemListCard> {
  static const _collapsed = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final visible = _expanded ? items : items.take(_collapsed).toList();
    final hidden = items.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
            child: _ItemRow(item: item),
          ),
        if (hidden > 0)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Show $hidden more'),
          )
        else if (_expanded && items.length > _collapsed)
          TextButton(
            onPressed: () => setState(() => _expanded = false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Show less'),
          ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final Map<String, dynamic> item;

  int? _int(String key) {
    final v = item[key];
    return v is num ? v.toInt() : null;
  }

  @override
  Widget build(BuildContext context) {
    final stock = _int('stock') ?? 0;
    final threshold = _int('threshold');
    final suggested = _int('suggested_reorder_qty');
    final out = stock <= 0;
    final low = threshold != null && stock <= threshold;

    final color = out
        ? AppTheme.danger(context)
        : low
            ? AppTheme.warning(context)
            : AppTheme.textTer(context);

    // Everything after the stock figure is optional: a row for a product with
    // no threshold or no reorder suggestion still has to read correctly.
    final detail = <String>[
      out ? 'Out of stock' : '$stock left',
      if (threshold != null && !out) 'reorder at $threshold',
      if (suggested != null && suggested > 0) 'suggest $suggested',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingLG,
        vertical: AppTheme.spacingMD,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Row(
        children: [
          Icon(
            out
                ? Icons.error_outline_rounded
                : low
                    ? Icons.warning_amber_rounded
                    : Icons.inventory_2_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: AppTheme.spacingMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? 'Unknown product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (out || low)
            TextButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.stockIn),
              child: const Text('Restock'),
            ),
        ],
      ),
    );
  }
}

/// One change, about to be applied to many products.
///
/// A bulk write is confirmed against the actual list — every product and the
/// exact movement — because the whole risk of "add 10 to everything low" is
/// that "everything low" is not what the user pictured.
class ChatBulkConfirmCard extends StatefulWidget {
  const ChatBulkConfirmCard({
    super.key,
    required this.action,
    required this.onDecision,
  });

  final Map<String, dynamic> action;
  final ValueChanged<bool> onDecision;

  @override
  State<ChatBulkConfirmCard> createState() => _ChatBulkConfirmCardState();
}

class _ChatBulkConfirmCardState extends State<ChatBulkConfirmCard> {
  static const _collapsed = 4;
  bool _decided = false;
  bool _confirmed = false;
  bool _expanded = false;

  void _decide(bool confirmed) {
    if (_decided) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _decided = true;
      _confirmed = confirmed;
    });
    widget.onDecision(confirmed);
  }

  List<Map<String, dynamic>> get _targets {
    final raw = widget.action['targets'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  String get _summary {
    final targets = _targets;
    final count = widget.action['count'] is num
        ? (widget.action['count'] as num).toInt()
        : targets.length;
    final label = widget.action['selector_label']?.toString() ?? 'products';
    final tool = widget.action['inner_tool']?.toString() ?? 'update_stock';
    final mode = widget.action['mode']?.toString() ?? 'fixed';
    final args = widget.action['args'];
    final plural = count == 1 ? 'product' : 'products';

    if (mode == 'to_min') {
      return 'Top $count $label back up to their thresholds';
    }
    if (mode == 'suggested') {
      return 'Draft a purchase order for each of $count $label';
    }
    if (args is Map) {
      final delta = args['qty_change'];
      if (tool == 'update_stock' && delta is num) {
        return '${delta > 0 ? 'Add' : 'Remove'} ${delta.abs()} units '
            '${delta > 0 ? 'to' : 'from'} each of $count $label';
      }
      final reorder = args['reorder_qty'];
      if (reorder is num) return 'Order $reorder units each for $count $plural';
      final threshold = args['new_threshold'];
      if (threshold is num) {
        return 'Set the reorder threshold to $threshold on $count $plural';
      }
      final counted = args['actual_stock'];
      if (counted is num) return 'Record a count of $counted on $count $plural';
    }
    return 'Apply this change to $count $plural';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary(context);

    if (_decided) {
      final done = _confirmed;
      final color = done ? AppTheme.success(context) : AppTheme.textTer(context);
      return Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Text(
            done ? 'Applying to all of them…' : 'Cancelled',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      );
    }

    final targets = _targets;
    final visible = _expanded ? targets : targets.take(_collapsed).toList();
    final hidden = targets.length - visible.length;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.tint(context, accent),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 17, color: accent),
              const SizedBox(width: AppTheme.spacingSM),
              Expanded(
                child: Text(
                  _summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingMD),
            for (final target in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _TargetRow(target: target),
              ),
            if (hidden > 0)
              TextButton(
                onPressed: () => setState(() => _expanded = true),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Show $hidden more'),
              ),
          ],
          const SizedBox(height: AppTheme.spacingMD),
          Row(
            children: [
              FilledButton(
                onPressed: () => _decide(true),
                child: Text('Confirm all ${targets.length}'),
              ),
              const SizedBox(width: AppTheme.spacingSM),
              TextButton(
                onPressed: () => _decide(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target});

  final Map<String, dynamic> target;

  @override
  Widget build(BuildContext context) {
    final stock = target['stock'] is num ? (target['stock'] as num).toInt() : 0;
    final change =
        target['change'] is num ? (target['change'] as num).toInt() : 0;
    final style = Theme.of(context).textTheme.bodySmall;

    return Row(
      children: [
        Expanded(
          child: Text(
            target['name']?.toString() ?? 'Unknown product',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: AppTheme.spacingSM),
        Text(
          change == 0 ? '$stock' : '$stock → ${stock + change}',
          style: style?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppTheme.textSec(context),
          ),
        ),
      ],
    );
  }
}

/// SKUs the assistant could not tell apart.
class ChatClarificationChips extends StatelessWidget {
  const ChatClarificationChips({
    super.key,
    required this.options,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> options;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Which one?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppTheme.spacingSM),
        Wrap(
          spacing: AppTheme.spacingSM,
          runSpacing: AppTheme.spacingSM,
          children: [
            for (final option in options)
              ActionChip(
                onPressed: () => onSelected(option),
                avatar: Icon(
                  Icons.inventory_2_outlined,
                  size: 15,
                  color: AppTheme.primary(context),
                ),
                label: Text(
                  // Real catalogs contain distinct products sharing a name, so
                  // the barcode is what actually tells two chips apart.
                  [
                    option['name']?.toString() ?? 'Unknown',
                    if (option['barcode'] != null) '· ${option['barcode']}',
                    if (option['stock'] != null) '· ${option['stock']} in stock',
                  ].join(' '),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A write the assistant wants confirmed before it happens.
class ChatConfirmCard extends StatefulWidget {
  const ChatConfirmCard({
    super.key,
    required this.action,
    required this.onDecision,
  });

  final Map<String, dynamic> action;
  final ValueChanged<bool> onDecision;

  @override
  State<ChatConfirmCard> createState() => _ChatConfirmCardState();
}

class _ChatConfirmCardState extends State<ChatConfirmCard> {
  bool _decided = false;
  bool _confirmed = false;

  void _decide(bool confirmed) {
    if (_decided) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _decided = true;
      _confirmed = confirmed;
    });
    widget.onDecision(confirmed);
  }

  String get _summary {
    final name = widget.action['product_name']?.toString() ?? 'this product';
    final args = widget.action['args'];
    if (args is Map) {
      final delta = args['qty_change'];
      if (delta is num && delta != 0) {
        return '${delta > 0 ? 'Add' : 'Remove'} ${delta.abs()} units'
            '${delta > 0 ? ' to' : ' from'} $name';
      }
      final reorder = args['reorder_qty'];
      if (reorder is num) return 'Order $reorder units of $name';
      final counted = args['actual_stock'];
      if (counted is num) return 'Set $name to $counted units';
      final threshold = args['new_threshold'];
      if (threshold is num) return 'Set $name reorder level to $threshold';
      final qty = args['qty'];
      if (qty is num) return 'Move $qty units of $name';
    }
    return 'Apply this change to $name';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary(context);

    if (_decided) {
      final done = _confirmed;
      final color =
          done ? AppTheme.success(context) : AppTheme.textTer(context);
      return Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: AppTheme.spacingSM),
          Text(
            done ? 'Confirmed' : 'Cancelled',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.tint(context, accent),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_summary, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.spacingMD),
          Row(
            children: [
              FilledButton(
                onPressed: () => _decide(true),
                child: const Text('Confirm'),
              ),
              const SizedBox(width: AppTheme.spacingSM),
              TextButton(
                onPressed: () => _decide(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the workspace has too little movement history to answer from.
class ChatNoHistoryCard extends StatelessWidget {
  const ChatNoHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 19,
            color: AppTheme.textTer(context),
          ),
          const SizedBox(width: AppTheme.spacingMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not enough movement recorded yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Record stock in and out for a while and the assistant can '
                  'start forecasting demand.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.spacingSM),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.stockIn),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Record stock in'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
