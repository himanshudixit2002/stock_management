import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/stock_provider.dart';

/// Warns that a report is built on a partial view of the ledger.
///
/// [StockProvider] loads at most [StockProvider.transactionFetchLimit]
/// transactions and has always exposed `transactionsTruncated` to say when it
/// hit that ceiling — but nothing in the app read the getter. So every report
/// built on `allTransactions` (P&L, ABC analysis, valuation trends, damage
/// history, forecasting, reorder suggestions, the executive summary) quietly
/// under-reported for any workspace busier than that, with nothing on screen to
/// suggest the figures were incomplete.
///
/// Raising the limit alone would only move the cliff; saying so is what makes
/// the numbers honest.
class TruncatedDataBanner extends StatelessWidget {
  const TruncatedDataBanner({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final truncated = context.select<StockProvider, bool>(
      (s) => s.transactionsTruncated,
    );
    if (!truncated) return const SizedBox.shrink();

    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.warningColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.warningColor.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: AppTheme.warningColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing the most recent '
                '${StockProvider.transactionFetchLimit} stock movements. '
                'Older activity is not included in these figures.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.textSec(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
