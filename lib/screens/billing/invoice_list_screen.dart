import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
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
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/provider_error_banner.dart';

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
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.viewInvoices)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Billing')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final billing = context.watch<BillingProvider>();
    final bs = context.watch<BillingSettingsProvider>().settings;
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final invoices = _filteredInvoices(billing.invoices);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Billing Reports',
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.billingReports),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
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
        ),
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

    if (billing.isLoading && billing.invoices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: const ShimmerLoading(itemCount: 5),
          ),
        ],
      );
    }

    if (invoices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.42,
            child: EmptyStateWidget(
              icon: Icons.receipt_long_rounded,
              title: 'No invoices yet',
              subtitle: 'Create your first invoice to get started',
              buttonText: canCreate ? 'New invoice' : null,
              onButtonPressed: canCreate
                  ? () => Navigator.pushNamed(context, AppRoutes.createInvoice)
                  : null,
            ),
          ),
        ],
      );
    }

    if (Responsive.listGridColumns(context) > 1) {
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Responsive.listGridColumns(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 0,
          mainAxisExtent: Responsive.listGridColumns(context) >= 3 ? 140 : 130,
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
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
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
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
            ),
            itemCount: statuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final s = statuses[index];
              final isSelected = _statusFilter == s;
              final label = s == null
                  ? 'All'
                  : s.name[0].toUpperCase() + s.name.substring(1);
              return FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primaryLight
                        : AppTheme.textPri(context),
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _statusFilter = s),
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.22),
                backgroundColor: AppTheme.card(context),
                checkmarkColor: AppTheme.primaryLight,
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
                fontSize: 10,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              invoice.invoiceNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.textTer(
                                  context,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                invoice.isPurchase ? 'Purchase' : 'Sales',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSec(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                invoice.statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            if (invoice.overdueDays > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.dangerColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${invoice.overdueDays}d',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.dangerColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          invoice.partyName,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateFormat.format(invoice.invoiceDate),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$symbol${numFormat.format(invoice.grandTotal)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (invoice.amountDue > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Due: $symbol${numFormat.format(invoice.amountDue)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.dangerColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
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
