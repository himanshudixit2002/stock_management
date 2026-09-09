import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../models/invoice_model.dart';
import '../../models/recurring_invoice_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/recurring_invoice_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';

/// Creates or edits a recurring billing schedule.
class RecurringInvoiceEditorScreen extends StatefulWidget {
  const RecurringInvoiceEditorScreen({super.key, this.schedule});

  final RecurringInvoiceModel? schedule;

  @override
  State<RecurringInvoiceEditorScreen> createState() =>
      _RecurringInvoiceEditorScreenState();
}

class _RecurringInvoiceEditorScreenState
    extends State<RecurringInvoiceEditorScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _paymentTerms = TextEditingController(text: '15');

  String _customerId = '';
  String _customerName = '';
  String _customerPhone = '';
  String _customerAddress = '';
  RecurrenceCadence _cadence = RecurrenceCadence.monthly;
  RecurringInvoiceStatus _status = RecurringInvoiceStatus.active;
  InvoiceStatus _issueStatus = InvoiceStatus.draft;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  DateTime? _nextRunAt;
  List<InvoiceItem> _items = [];

  bool get _isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    if (schedule != null) {
      _title.text = schedule.title;
      _notes.text = schedule.notes;
      _paymentTerms.text = '${schedule.paymentTermDays}';
      _customerId = schedule.customerId;
      _customerName = schedule.customerName;
      _customerPhone = schedule.customerPhone;
      _customerAddress = schedule.customerAddress;
      _cadence = schedule.cadence;
      _status = schedule.status;
      _issueStatus = schedule.issueStatus;
      _startDate = schedule.startDate;
      _endDate = schedule.endDate;
      _nextRunAt = schedule.nextRunAt;
      _items = [...schedule.items];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _paymentTerms.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final customers = context.read<CustomerProvider>().customers;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Bill to',
      selectedValue: _customerId.isEmpty ? null : _customerId,
      items: [
        for (final CustomerModel customer in customers)
          PickerItem(
            value: customer.id,
            label: customer.name,
            subtitle: customer.phone,
            icon: Icons.person_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final customer = customers.where((c) => c.id == selected).firstOrNull;
    if (customer == null) return;
    setState(() {
      _customerId = customer.id;
      _customerName = customer.name;
      _customerPhone = customer.phone;
      _customerAddress = customer.address;
    });
  }

  Future<void> _addItem() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Add a line',
    );
    if (picked == null || !mounted) return;
    final defaultTax = context.read<BillingSettingsProvider>().settings.defaultTaxRate;
    setState(() {
      _items = [
        ..._items,
        InvoiceItem(
          productId: picked.id,
          productName: picked.name,
          quantity: 1,
          unit: picked.unit,
          unitPrice: picked.sellingPrice,
          taxRate: defaultTax,
        ),
      ];
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: start ? 'First invoice date' : 'Stop after',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        // A schedule that has never run bills first on its start date. One
        // that has already issued invoices keeps its place in the cycle.
        if (widget.schedule == null ||
            widget.schedule!.generatedCount == 0) {
          _nextRunAt = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerId.isEmpty) {
      showErrorSnackBar(context, 'Choose who this bills.');
      return;
    }
    final items = _items.where((i) => i.quantity > 0).toList();
    if (items.isEmpty) {
      showErrorSnackBar(context, 'Add at least one line to bill.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<RecurringInvoiceProvider>();
    final now = DateTime.now();
    final existing = widget.schedule;

    final schedule = RecurringInvoiceModel(
      id: existing?.id ?? '',
      title: _title.text.trim(),
      customerId: _customerId,
      customerName: _customerName,
      customerPhone: _customerPhone,
      customerAddress: _customerAddress,
      items: items,
      taxLabel: context.read<BillingSettingsProvider>().settings.taxLabel,
      notes: _notes.text.trim(),
      paymentTermDays: int.tryParse(_paymentTerms.text.trim()) ?? 15,
      issueStatus: _issueStatus,
      cadence: _cadence,
      status: _status,
      startDate: _startDate,
      endDate: _endDate,
      nextRunAt: _nextRunAt ?? _startDate,
      lastRunAt: existing?.lastRunAt,
      generatedCount: existing?.generatedCount ?? 0,
      generatedInvoiceIds: existing?.generatedInvoiceIds ?? const [],
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.update(schedule)
        : (await provider.add(schedule)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Schedule updated.' : 'Schedule created.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _delete() async {
    final schedule = widget.schedule;
    if (schedule == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this schedule?',
      message:
          'Invoices it has already issued stay exactly where they are. Only '
          'the schedule goes.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<RecurringInvoiceProvider>();
    final ok = await provider.remove(schedule.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Schedule deleted.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageRecurringInvoices,
      featureName: 'Billing Schedules',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<RecurringInvoiceProvider>().isBusy;
    final symbol = Money.symbolOf(context);
    final preview = RecurringInvoiceProvider.totalOf(
      RecurringInvoiceModel(
        id: '',
        customerId: _customerId,
        items: _items,
        startDate: _startDate,
        nextRunAt: _nextRunAt ?? _startDate,
        createdAt: _startDate,
        updatedAt: _startDate,
      ),
    );

    return AppScreenScaffold(
      icon: Icons.event_repeat_rounded,
      title: _isEditing ? 'Edit Schedule' : 'New Schedule',
      subtitle: preview > 0
          ? '${Money.withSymbol(symbol, preview)} per invoice'
          : null,
      iconColor: AppTheme.infoColor,
      actions: [
        if (_isEditing)
          IconButton(
            onPressed: busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
          ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'Who and what',
              icon: Icons.person_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _title,
                  label: 'Schedule name',
                  hint: 'e.g. Acme — monthly retainer',
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Name the schedule'
                      : null,
                ),
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Bill to',
                  icon: Icons.person_rounded,
                  value: _customerName.isEmpty ? null : _customerName,
                  placeholder: 'Choose a customer',
                  detail: _customerPhone.isEmpty ? null : _customerPhone,
                  onTap: _pickCustomer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Lines',
              icon: Icons.receipt_long_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
              children: [
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nothing to bill yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _items.length; i++)
                    _ItemEditor(
                      item: _items[i],
                      symbol: symbol,
                      onChanged: (item) => setState(() {
                        final next = [..._items];
                        next[i] = item;
                        _items = next;
                      }),
                      onRemove: () => setState(() {
                        final next = [..._items]..removeAt(i);
                        _items = next;
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Cadence',
              icon: Icons.autorenew_rounded,
              index: 2,
              children: [
                DropdownButtonFormField<RecurrenceCadence>(
                  initialValue: _cadence,
                  decoration: const InputDecoration(labelText: 'Bills every'),
                  items: [
                    for (final cadence in RecurrenceCadence.values)
                      DropdownMenuItem(
                        value: cadence,
                        child: Text(
                          RecurringInvoiceModel.cadenceLabelOf(cadence),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _cadence = value);
                  },
                ),
                const SizedBox(height: 12),
                _DateRow(
                  label: 'First invoice',
                  value: _dateFormat.format(_startDate),
                  onTap: () => _pickDate(start: true),
                ),
                _DateRow(
                  label: 'Stop after',
                  value: _endDate == null
                      ? 'No end date'
                      : _dateFormat.format(_endDate!),
                  onTap: () => _pickDate(start: false),
                  onClear: _endDate == null
                      ? null
                      : () => setState(() => _endDate = null),
                ),
                if (_nextRunAt != null && _isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Next invoice ${_dateFormat.format(_nextRunAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _paymentTerms,
                  label: 'Payment terms (days)',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InvoiceStatus>(
                  initialValue: _issueStatus,
                  decoration: const InputDecoration(
                    labelText: 'Issue invoices as',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: InvoiceStatus.draft,
                      child: Text('Draft — review before sending'),
                    ),
                    DropdownMenuItem(
                      value: InvoiceStatus.sent,
                      child: Text('Sent — treat as issued immediately'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _issueStatus = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RecurringInvoiceStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final status in RecurringInvoiceStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(switch (status) {
                          RecurringInvoiceStatus.active => 'Active',
                          RecurringInvoiceStatus.paused => 'Paused',
                          RecurringInvoiceStatus.ended => 'Ended',
                        }),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Notes',
              icon: Icons.sticky_note_2_rounded,
              index: 3,
              children: [
                CustomTextField(
                  controller: _notes,
                  label: 'Notes on each invoice',
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isEditing ? 'Save changes' : 'Create schedule'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invoices are issued when someone presses Generate — there is no '
              'background scheduler, so nothing is billed while the app is '
              'closed.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: 18,
              color: AppTheme.textSec(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.item,
    required this.symbol,
    required this.onChanged,
    required this.onRemove,
  });

  final InvoiceItem item;
  final String symbol;
  final ValueChanged<InvoiceItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.item.quantity}',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.item.unitPrice.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.item.copyWith(quantity: int.tryParse(value) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: '${widget.symbol}/unit',
                      isDense: true,
                    ),
                    onChanged: (value) => widget.onChanged(
                      widget.item.copyWith(
                        unitPrice: double.tryParse(value) ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
