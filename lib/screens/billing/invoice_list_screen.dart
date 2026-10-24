import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/responsive.dart';
import '../../utils/invoice_search.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/provider_error_banner.dart';
import '../../utils/currency.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  InvoiceType? _typeFilter;
  InvoiceStatus? _statusFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _numFormat = NumberFormat('#,##0.00');

  Color _statusColor(BuildContext context, InvoiceStatus status) {
    final outline = Theme.of(context).colorScheme.outline;
    return switch (status) {
      InvoiceStatus.draft => outline,
      InvoiceStatus.sent => AppTheme.infoColor,
      InvoiceStatus.partiallyPaid => AppTheme.warningColor,
      InvoiceStatus.paid => AppTheme.successColor,
      InvoiceStatus.overdue => AppTheme.dangerColor,
      InvoiceStatus.cancelled => outline,
      InvoiceStatus.refunded => AppTheme.indigoColor,
    };
  }

  List<InvoiceModel> _filteredInvoices(List<InvoiceModel> invoices) {
    var result = invoices;
    if (_typeFilter != null) {
      result = result.where((i) => i.invoiceType == _typeFilter).toList();
    }
    if (_statusFilter != null) {
      result = result.where((i) => i.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result
          .where((i) => invoiceMatchesSearch(i, _searchQuery))
          .toList();
    }
    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefreshInvoices() async {
    final cid = context.read<ProductProvider>().companyId;
    if (cid.isEmpty) return;
    context.read<BillingProvider>().initialize(companyId: cid);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewInvoices,
      featureName: 'Invoices',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = Money.symbolOrFallback(bs.currencySymbol);
    final invoices = _filteredInvoices(billing.invoices);

    return AppScreenScaffold(
      icon: Icons.receipt_long_rounded,
      title: 'Billing',
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded),
          tooltip: 'Billing Reports',
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.billingReports),
        ),
      ],
      body: Column(
            children: [
              if (billing.errorMessage != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    8,
                    Responsive.horizontalPadding(context),
                    0,
                  ),
                  child: ProviderErrorBanner(
                    message: billing.errorMessage!,
                    onDismiss: () =>
                        context.read<BillingProvider>().clearError(),
                    onRetry: () {
                      final cid = context.read<ProductProvider>().companyId;
                      if (cid.isNotEmpty) {
                        context.read<BillingProvider>().initialize(
                          companyId: cid,
                        );
                      }
                    },
                  ),
                ),
              _buildTypeToggle(),
              _buildStatsBar(billing, sym),
              _buildSearchAndFilters(),
              Expanded(
                child: RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _onRefreshInvoices,
                  child: _buildInvoiceScrollable(
                    context,
                    billing: billing,
                    invoices: invoices,
                    sym: sym,
                    user: user,
                  ),
                ),
              ),
            ],
          ),
      floatingActionButton:
          (user?.hasPermission(AppPermissions.createInvoices) ?? false)
          ? Semantics(
              label: 'New invoice',
              button: true,
              child: FloatingActionButton.extended(
                tooltip: 'New invoice',
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.createInvoice),
                icon: const Icon(Icons.add),
                label: const Text('New Invoice'),
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            )
          : null,
    );
  }

  Widget _buildInvoiceScrollable(
    BuildContext context, {
    required BillingProvider billing,
    required List<InvoiceModel> invoices,
    required String sym,
    required UserModel? user,
  }) {
    final hPad = Responsive.horizontalPadding(context);
    final canCreate =
        user?.hasPermission(AppPermissions.createInvoices) ?? false;

    // Room under the last card for the New Invoice button, which otherwise
    // sat on top of it.
    final bottomPad = canCreate ? 96.0 : 16.0;

    if (billing.isLoading && billing.invoices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
        children: const [ShimmerLoading(itemCount: 5)],
      );
    }

    if (invoices.isEmpty) {
      final filtered = _statusFilter != null || _searchQuery.isNotEmpty;
      // Sized by the empty state itself rather than a fraction of the screen
      // height, which overflowed short phones, landscape and large text.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, bottomPad),
        children: [
          filtered
              ? const EmptyStateWidget(
                  icon: Icons.search_off_rounded,
                  title: 'No matching invoices',
                  subtitle: 'Try another search or status filter',
                )
              : EmptyStateWidget(
                  icon: Icons.receipt_long_rounded,
                  title: 'No invoices yet',
                  subtitle: 'Create your first invoice to get started',
                  buttonText: canCreate ? 'New invoice' : null,
                  onButtonPressed: canCreate
                      ? () => Navigator.pushNamed(
                          context,
                          AppRoutes.createInvoice,
                        )
                      : null,
                ),
        ],
      );
    }

    if (Responsive.listGridColumns(context) > 1) {
      // Grid cells have a fixed height, so it follows the text size: the old
      // fixed 130/140 px clipped cards at larger text.
      final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, bottomPad),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Responsive.listGridColumns(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 0,
          mainAxisExtent: 44 + 64 * textScale,
        ),
        itemCount: invoices.length,
        itemBuilder: (context, index) {
          return AnimatedListItem(
            index: index,
            child: _InvoiceCard(
              invoice: invoices[index],
              symbol: sym,
              dateFormat: _dateFormat,
              numFormat: _numFormat,
              statusColor: _statusColor(context, invoices[index].status),
            ),
          );
        },
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, bottomPad),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        return AnimatedListItem(
          index: index,
          child: _InvoiceCard(
            invoice: invoices[index],
            symbol: sym,
            dateFormat: _dateFormat,
            numFormat: _numFormat,
            statusColor: _statusColor(context, invoices[index].status),
          ),
        );
      },
    );
  }

  Widget _buildTypeToggle() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        8,
        Responsive.horizontalPadding(context),
        0,
      ),
      child: Row(
        children: [
          _typeChip('All', null),
          const SizedBox(width: 6),
          _typeChip('Sales', InvoiceType.sales),
          const SizedBox(width: 6),
          _typeChip('Purchase', InvoiceType.purchase),
        ],
      ),
    );
  }

  Widget _typeChip(String label, InvoiceType? type) {
    final selected = _typeFilter == type;
    final isDark = AppTheme.isDark(context);
    final unselectedBg = isDark
        ? AppTheme.card(context)
        : AppTheme.primaryColor.withValues(alpha: 0.06);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? null
                : Border.all(color: AppTheme.dividerC(context), width: 1),
            color: selected ? AppTheme.primaryColor : unselectedBg,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.textPri(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(BillingProvider billing, String sym) {
    List<InvoiceModel> source = billing.invoices;
    if (_typeFilter != null) {
      source = source.where((i) => i.invoiceType == _typeFilter).toList();
    }
    final invoiced = source
        .where((i) => !i.isCancelled)
        .fold(0.0, (s, i) => s + i.grandTotal);
    final received = source
        .where((i) => !i.isCancelled)
        .fold(0.0, (s, i) => s + i.amountPaid);
    final outstanding = invoiced - received;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 8,
      ),
      child: Row(
        children: [
          _StatChip(
            label: 'Invoiced',
            value: '$sym${_numFormat.format(invoiced)}',
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Received',
            value: '$sym${_numFormat.format(received)}',
            color: AppTheme.successColor,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Outstanding',
            value: '$sym${_numFormat.format(outstanding)}',
            color: AppTheme.dangerColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final statuses = [null, ...InvoiceStatus.values];
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
          ),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: AppTheme.textPri(context)),
            decoration: InputDecoration(
              hintText: 'Search invoice #, customer/vendor, phone, amount…',
              hintStyle: TextStyle(
                color: AppTheme.textSec(context),
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppTheme.inputFill(context),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: AppTheme.textSec(context),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: 18,
                        color: AppTheme.textSec(context),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.inputBorder(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.primaryColor,
                  width: 2,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          // Follows the text size; a fixed 36 px clipped the chips at 1.3x.
          height: MediaQuery.textScalerOf(context).scale(12) * 1.3 + 22,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
            ),
            itemCount: statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final s = statuses[index];
              final isSelected = _statusFilter == s;
              // The status's own label ("Partially paid"), not its enum name,
              // which read "PartiallyPaid".
              final label = s == null ? 'All' : InvoiceModel.labelFor(s);
              // Light teal on a pale teal fill was about 1.4:1.
              final selectedFg = AppTheme.isDark(context)
                  ? AppTheme.primaryLight
                  : AppTheme.primaryDark;
              return FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? selectedFg
                        : AppTheme.textPri(context),
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _statusFilter = s),
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.16),
                backgroundColor: AppTheme.card(context),
                checkmarkColor: selectedFg,
                side: BorderSide(
                  color: isSelected
                      ? Colors.transparent
                      : AppTheme.dividerC(context),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassPanel(
        borderRadius: 12,
        useContentVariant: true,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final InvoiceModel invoice;
  final String symbol;
  final DateFormat dateFormat;
  final NumberFormat numFormat;
  final Color statusColor;

  const _InvoiceCard({
    required this.invoice,
    required this.symbol,
    required this.dateFormat,
    required this.numFormat,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        borderRadius: 14,
        useContentVariant: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.invoiceDetail,
              arguments: invoice.id,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      invoice.isPurchase
                          ? Icons.shopping_bag_rounded
                          : Icons.receipt_long_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Number and amount share the first line; the pills wrap on
                  // their own line. They used to share one unshrinkable row
                  // with the number, which overflowed every phone width.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                invoice.invoiceNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppTheme.textPri(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$symbol${numFormat.format(invoice.grandTotal)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppTheme.textPri(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                invoice.partyName.isNotEmpty
                                    ? invoice.partyName
                                    : '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSec(context),
                                ),
                              ),
                            ),
                            if (invoice.amountDue > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Due $symbol${numFormat.format(invoice.amountDue)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.dangerColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Pill(
                              label: invoice.isPurchase ? 'Purchase' : 'Sales',
                              color: AppTheme.textSec(context),
                              fill: AppTheme.textTer(
                                context,
                              ).withValues(alpha: 0.12),
                            ),
                            _Pill(
                              label: invoice.statusLabel,
                              color: statusColor,
                              fill: statusColor.withValues(alpha: 0.12),
                            ),
                            if (invoice.overdueDays > 0)
                              _Pill(
                                label: '${invoice.overdueDays}d overdue',
                                color: AppTheme.dangerColor,
                                fill: AppTheme.dangerColor.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Text(
                                dateFormat.format(invoice.invoiceDate),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSec(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.fill});

  final String label;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
