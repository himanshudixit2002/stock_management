import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/animations.dart';
import '../../../services/report_analytics_service.dart';
import '../../../widgets/floating_nav_padding.dart';

class CustomReportBuilderTab extends StatefulWidget {
  const CustomReportBuilderTab({super.key});

  @override
  State<CustomReportBuilderTab> createState() => _CustomReportBuilderTabState();
}

class _CustomReportBuilderTabState extends State<CustomReportBuilderTab> {
  String _groupBy = 'category';
  bool _enablePoPComparison = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

    final currentTx = stockProvider.recentTransactions;
    final products = productProvider.products;
    final pMap = {for (final p in products) p.id: p};

    final analytics = ReportAnalyticsService();
    final rows = analytics.generateCustomReport(
      transactions: currentTx,
      productMap: pMap,
      groupBy: _groupBy,
    );

    final filteredRows = rows.where((r) {
      if (_searchQuery.isEmpty) return true;
      return r.groupName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    double totalRevenue = 0;
    double totalProfit = 0;

    for (final r in filteredRows) {
      totalRevenue += r.salesRevenue;
      totalProfit += r.profit;
    }

    final avgMargin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0.0;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: FadeSlideIn(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + floatingNavContentInset(context) + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassPanel(
                padding: const EdgeInsets.all(14),
                borderRadius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded, color: AppTheme.primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Dimension & Grouping Selector',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                          ],
                        ),
                        FilterChip(
                          selected: _enablePoPComparison,
                          label: const Text('Compare PoP'),
                          avatar: Icon(
                            _enablePoPComparison ? Icons.check_circle_rounded : Icons.circle_outlined,
                            size: 16,
                            color: _enablePoPComparison ? Colors.white : AppTheme.textSec(context),
                          ),
                          onSelected: (val) {
                            setState(() => _enablePoPComparison = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildChip('Category', 'category'),
                        _buildChip('User / Cashier', 'user'),
                        _buildChip('Vendor', 'vendor'),
                        _buildChip('Transaction Type', 'type'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search groups...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _statBox('Est. Revenue', currency.format(totalRevenue), AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBox('Est. Profit', currency.format(totalProfit), Colors.teal),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statBox('Avg Margin', '${avgMargin.toStringAsFixed(1)}%', Colors.purpleAccent),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              filteredRows.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Text(
                        'No matching records found for this dimension',
                        style: TextStyle(color: AppTheme.textSec(context)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredRows.length,
                      itemBuilder: (context, index) {
                        final row = filteredRows[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: GlassPanel(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            borderRadius: 12,
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(top: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _groupBy == 'category'
                                      ? Icons.category_rounded
                                      : (_groupBy == 'user'
                                          ? Icons.person_rounded
                                          : (_groupBy == 'vendor' ? Icons.store_rounded : Icons.swap_horiz_rounded)),
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                row.groupName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Rev: ${currency.format(row.salesRevenue)} • Profit: ${currency.format(row.profit)} (${row.profitMarginPct.toStringAsFixed(1)}%)',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: row.profit >= 0 ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${row.stockOutQty} Out',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: row.profit >= 0 ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                              children: [
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _detailItem('Stock In', '${row.stockInQty} pcs'),
                                    _detailItem('Stock Out', '${row.stockOutQty} pcs'),
                                    _detailItem('Damaged', '${row.damageQty} pcs (${currency.format(row.damageValue)})'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, String value) {
    final selected = _groupBy == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (sel) {
        if (sel) setState(() => _groupBy = value);
      },
    );
  }

  Widget _statBox(String title, String val, Color col) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      borderRadius: 10,
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: AppTheme.textSec(context))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: col),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textSec(context))),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
