import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/stock_take_model.dart';
import '../../providers/stock_take_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../utils/dialogs.dart';

class StockTakeCountScreen extends StatefulWidget {
  final StockTakeModel stockTake;

  const StockTakeCountScreen({super.key, required this.stockTake});

  @override
  State<StockTakeCountScreen> createState() => _StockTakeCountScreenState();
}

class _StockTakeCountScreenState extends State<StockTakeCountScreen>
    with SingleTickerProviderStateMixin {
  late List<StockTakeItem> _items;
  late List<TextEditingController> _controllers;
  bool _isSubmitting = false;
  late AnimationController _pulseController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.stockTake.items);
    _controllers = _items.map((item) {
      return TextEditingController(
        text: item.countedQty > 0 ? item.countedQty.toString() : '',
      );
    }).toList();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _nextUncountedIndex {
    for (int i = 0; i < _items.length; i++) {
      if (_controllers[i].text.isEmpty) return i;
    }
    return null;
  }

  int? _nextUncountedIndexAfter(int fromIndex) {
    for (int i = fromIndex + 1; i < _items.length; i++) {
      if (_controllers[i].text.isEmpty) return i;
    }
    return null;
  }

  int get _completionPercent =>
      _items.isEmpty ? 100 : ((_countedItems / _items.length) * 100).round();

  int _variance(int index) {
    final counted = int.tryParse(_controllers[index].text) ?? 0;
    return counted - _items[index].expectedQty;
  }

  int get _totalVarianceItems {
    int count = 0;
    for (int i = 0; i < _items.length; i++) {
      if (_variance(i) != 0) count++;
    }
    return count;
  }

  int get _countedItems {
    int count = 0;
    for (final c in _controllers) {
      if (c.text.isNotEmpty) count++;
    }
    return count;
  }

  Future<void> _saveDraft() async {
    final updatedItems = <StockTakeItem>[];
    for (int i = 0; i < _items.length; i++) {
      final counted = int.tryParse(_controllers[i].text) ?? 0;
      updatedItems.add(_items[i].copyWith(
        countedQty: counted,
        variance: counted - _items[i].expectedQty,
      ));
    }

    final updated = widget.stockTake.copyWith(
      items: updatedItems,
      status: StockTakeStatus.inProgress,
    );

    final success =
        await context.read<StockTakeProvider>().updateStockTake(updated);

    if (!context.mounted) return;
    if (success) {
      showSuccessSnackBar(context, 'Draft saved');
    } else {
      showErrorSnackBar(context, 'Failed to save draft');
    }
  }

  Future<void> _submit() async {
    final uncounted = _items.length - _countedItems;
    if (uncounted > 0) {
      final proceed = await showConfirmDialog(
        context,
        title: 'Uncounted Items',
        message: '$uncounted item${uncounted == 1 ? '' : 's'} haven\'t been counted yet. '
            'They will be recorded as 0. Continue?',
        confirmLabel: 'Submit Anyway',
        icon: Icons.warning_amber_rounded,
        iconColor: AppTheme.warningColor,
        confirmColor: AppTheme.primaryColor,
      );
      if (!proceed) return;
    }

    setState(() => _isSubmitting = true);

    final updatedItems = <StockTakeItem>[];
    for (int i = 0; i < _items.length; i++) {
      final counted = int.tryParse(_controllers[i].text) ?? 0;
      updatedItems.add(_items[i].copyWith(
        countedQty: counted,
        variance: counted - _items[i].expectedQty,
      ));
    }

    final updated = widget.stockTake.copyWith(items: updatedItems);
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;

    final success = await context.read<StockTakeProvider>().completeStockTake(
          stockTake: updated,
          userId: user?.uid ?? '',
          userName: user?.name ?? '',
        );

    if (!context.mounted) return;
    setState(() => _isSubmitting = false);
    if (success) {
      showSuccessSnackBar(context, 'Stock take completed and adjustments recorded');
      Navigator.pop(context);
    } else {
      showErrorSnackBar(context, context.read<StockTakeProvider>().errorMessage ?? 'Failed to complete stock take');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted =
        widget.stockTake.status == StockTakeStatus.completed;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBarTitleRow(
                icon: Icons.fact_check_rounded,
                color: AppTheme.indigoColor,
                title: widget.stockTake.name,
              ),
              if (_items.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '$_countedItems of ${_items.length} counted ($_completionPercent%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!isCompleted)
              TextButton.icon(
                onPressed: _saveDraft,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Draft'),
              ),
          ],
        ),
        bottomNavigationBar: isCompleted
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _summaryChip(
                              'Total',
                              '${_items.length}',
                              AppTheme.textPri(context),
                            ),
                            _summaryChip(
                              'Counted',
                              '$_countedItems',
                              AppTheme.primaryColor,
                            ),
                            _summaryChip(
                              'Variance',
                              '$_totalVarianceItems',
                              _totalVarianceItems > 0
                                  ? AppTheme.dangerColor
                                  : AppTheme.successColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Submit & Finalize'),
                      ),
                    ],
                  ),
                ),
              ),
        body: _items.isEmpty
            ? const EmptyStateWidget(
                icon: Icons.inventory_2_outlined,
                title: 'No Items',
                subtitle: 'This stock take has no items to count.',
              )
            : Column(
                children: [
                  LinearProgressIndicator(
                    value: _items.isEmpty ? 1.0 : _countedItems / _items.length,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    minHeight: 4,
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                      controller: _scrollController,
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                  final item = _items[index];
                  final variance = _variance(index);
                  final hasVariance = _controllers[index].text.isNotEmpty &&
                      variance != 0;
                  final isNextUncounted = !isCompleted &&
                      _nextUncountedIndex == index;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: isNextUncounted
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.15 + (_pulseController.value * 0.2),
                                      ),
                                      blurRadius: 12 + (_pulseController.value * 8),
                                      spreadRadius: _pulseController.value * 2,
                                    ),
                                  ],
                                )
                              : null,
                          child: child,
                        );
                      },
                      child: GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: hasVariance
                                        ? AppTheme.dangerColor
                                            .withValues(alpha: 0.12)
                                        : (_controllers[index].text.isNotEmpty
                                            ? AppTheme.successColor
                                                .withValues(alpha: 0.12)
                                            : AppTheme.inputFill(context)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: hasVariance
                                            ? AppTheme.dangerColor
                                            : (_controllers[index]
                                                    .text
                                                    .isNotEmpty
                                                ? AppTheme.successColor
                                                : AppTheme.textSec(context)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: AppTheme.textPri(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Expected',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.inputFill(context),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${item.expectedQty}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPri(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Counted',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: _controllers[index],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        readOnly: isCompleted,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          hintText: '0',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: hasVariance
                                                  ? AppTheme.dangerColor
                                                  : AppTheme.inputBorder(context),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: AppTheme.primaryColor,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Variance',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hasVariance
                                              ? AppTheme.dangerColor
                                                  .withValues(alpha: 0.08)
                                              : (_controllers[index]
                                                      .text
                                                      .isNotEmpty
                                                  ? AppTheme.successColor
                                                      .withValues(alpha: 0.08)
                                                  : AppTheme.inputFill(context)),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _controllers[index].text.isEmpty
                                              ? '-'
                                              : (variance >= 0
                                                  ? '+$variance'
                                                  : '$variance'),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: hasVariance
                                                ? AppTheme.dangerColor
                                                : (_controllers[index]
                                                        .text
                                                        .isNotEmpty
                                                    ? AppTheme.successColor
                                                    : AppTheme.textSec(context)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (!isCompleted) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      _controllers[index].text = '0';
                                      _controllers[index].selection =
                                          TextSelection.collapsed(
                                        offset: _controllers[index].text.length,
                                      );
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.exposure_zero, size: 16),
                                    label: const Text('Mark as Zero'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.textSec(context),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: _nextUncountedIndexAfter(index) != null
                                        ? () {
                                            final nextIdx = _nextUncountedIndexAfter(index)!;
                                            final itemHeight = 200.0;
                                            _scrollController.animateTo(
                                              (nextIdx * itemHeight).clamp(
                                                0.0,
                                                _scrollController.position.maxScrollExtent,
                                              ),
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(Icons.skip_next, size: 16),
                                    label: const Text('Skip'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.textSec(context),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ),
                  );
                },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSec(context),
          ),
        ),
      ],
    );
  }
}
