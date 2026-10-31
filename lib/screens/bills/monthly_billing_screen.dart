import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/theme/app_theme.dart';
import '../../services/bill_pdf_service.dart';
import '../../services/customer_cache_service.dart';
import '../../services/user_session.dart';
import '../database/database_helper.dart';
import 'bill_customer_detail_screen.dart';

class MonthlyBillingScreen extends StatefulWidget {
  const MonthlyBillingScreen({super.key});

  @override
  State<MonthlyBillingScreen> createState() => _MonthlyBillingScreenState();
}

class _MonthlyBillingScreenState extends State<MonthlyBillingScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _searchController = TextEditingController();
  List<Map<String, Object?>> _bills = [];
  String _searchQuery = '';
  bool _loading = false;
  bool _sharing = false;

  static const double _serviceCharge = 60;
  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  String _text(Object? value, [String fallback = '']) => value?.toString() ?? fallback;

  String _money(Object? value) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format((value as num?)?.toDouble() ?? 0);

  List<Map<String, Object?>> get _filteredBills {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _bills;
    return _bills.where((bill) =>
      _text(bill['name']).toLowerCase().contains(query) ||
      _text(bill['mobile']).toLowerCase().contains(query),
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _generateBills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select a billing month',
    );
    if (date == null || !mounted) return;
    setState(() => _month = DateTime(date.year, date.month));
    await _generateBills();
  }

  Future<void> _loadSavedBills() async {
    if (mounted) setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT b.*, c.name, c.mobile, c.address, c.milk_type
        FROM bills b INNER JOIN customers c ON c.id = b.customer_id
        WHERE b.billing_month = ?
        ORDER BY c.name COLLATE NOCASE ASC
      ''', [_monthKey]);
      if (!mounted) return;
      setState(() {
        _bills = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load bills: $error');
    }
  }

  Future<void> _generateBills() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await CustomerCacheService.refresh();
      final db = await DatabaseHelper.instance.database;
      final start = DateFormat('yyyy-MM-dd').format(DateTime(_month.year, _month.month));
      final end = DateFormat('yyyy-MM-dd').format(DateTime(_month.year, _month.month + 1));
      await db.transaction((txn) async {
        final customers = await txn.query('customers');
        for (final customer in customers) {
          final id = customer['id'] as String;
          final milk = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity * rate), 0) AS amount
            FROM milk_entries
            WHERE customer_id = ? AND entry_date >= ? AND entry_date < ? AND delivered = 1
          ''', [id, start, end]);
          final extras = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity * unit_price), 0) AS amount
            FROM customer_daily_products WHERE customer_id = ? AND entry_date >= ? AND entry_date < ?
          ''', [id, start, end]);
          final previous = await txn.query(
            'bills', columns: ['final_balance'],
            where: 'customer_id = ? AND billing_month < ?',
            whereArgs: [id, _monthKey],
            orderBy: 'billing_month DESC', limit: 1,
          );
          final payment = await txn.rawQuery('''
            SELECT COALESCE(SUM(amount), 0) AS amount FROM payments
            WHERE customer_id = ? AND payment_date >= ? AND payment_date < ?
          ''', [id, start, end]);
          final milkAmount = (milk.first['amount'] as num).toDouble() + (extras.first['amount'] as num).toDouble();
          final previousDue = previous.isEmpty ? 0.0 : (previous.first['final_balance'] as num).toDouble();
          final payments = (payment.first['amount'] as num).toDouble();
          final rawBalance = milkAmount + _serviceCharge + previousDue - payments;
          final balance = rawBalance > 0 ? rawBalance : 0.0;
          final bill = <String, Object?>{
            'id': '${id}_$_monthKey',
            'customer_id': id,
            'billing_month': _monthKey,
            'milk_amount': milkAmount,
            'service_charge': _serviceCharge,
            'previous_due': previousDue,
            'payments_received': payments,
            'final_balance': balance,
            'status': rawBalance <= 0 ? 'paid' : 'unpaid',
            'created_at': DateTime.now().toIso8601String(),
          };
          await txn.insert('bills', bill, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      await _loadSavedBills();
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _message('Could not update bills: $error');
      }
    }
  }

  Future<void> _shareBill(Map<String, Object?> bill) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final customers = await db.query('customers', where: 'id = ?', whereArgs: [bill['customer_id']], limit: 1);
      if (customers.isEmpty) throw Exception('Customer not found');
      final monthParts = _text(bill['billing_month']).split('-');
      final year = int.parse(monthParts[0]);
      final month = int.parse(monthParts[1]);
      final start = DateFormat('yyyy-MM-dd').format(DateTime(year, month));
      final end = DateFormat('yyyy-MM-dd').format(DateTime(year, month + 1));
      final entries = await db.query(
        'milk_entries',
        where: 'customer_id = ? AND entry_date >= ? AND entry_date < ? AND delivered = 1',
        whereArgs: [bill['customer_id'], start, end],
        orderBy: 'entry_date ASC',
      );
      await BillPdfService.generateAndShare(
        customer: customers.first,
        bill: bill,
        entries: entries,
        businessName: 'Atul Milk',
        businessPhone: '7030009085',
        businessAddress: 'Nashik',
        upiId: 'prashantsdeore15-1@oksbi',
        payeeName: 'Prashant Deore',
      );
    } catch (error) {
      _message('Could not share bill PDF: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _createCustomBill() async {
    await CustomerCacheService.refresh();
    final customerRows = await DatabaseHelper.instance.getCustomers();
    final milkRates = await DatabaseHelper.instance.getMilkRates();
    // Milk Rates are saved to the user's Firestore settings. The local SQLite
    // table can still contain the installation defaults, so use the saved
    // rates whenever they are available.
    if (UserSession.isActive && UserSession.can('settings', 'view')) {
      try {
        final snapshot = await UserSession.collection('settings').doc('milk_rates').get();
        final savedRates = snapshot.data()?['extra_item_rates'];
        if (savedRates is Map) {
          for (final type in const ['cow_milk', 'buffalo_milk', 'fresh_milk']) {
            final value = savedRates[type];
            if (value is num && value > 0) milkRates[type] = value.toDouble();
          }
        }
      } catch (_) {
        // Keep the locally saved rates available if Firestore is offline.
      }
    }
    if (!mounted) return;
    if (customerRows.isEmpty) {
      _message('Add a customer before creating a bill.');
      return;
    }

    final selectedValues = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _CustomBillDialog(customers: customerRows, milkRates: milkRates),
    );
    if (selectedValues == null || !mounted) return;

    final customer = customerRows.firstWhere((row) => row['id'] == selectedValues!['customer_id']);
    final now = DateTime.now();
    final bill = <String, Object?>{
      'id': 'CUSTOM-${DateFormat('yyyyMMdd-HHmm').format(now)}',
      'billing_month': _monthKey,
      'milk_amount': selectedValues['milk_amount'],
      'milk_rate': selectedValues['rate'],
      'total_milk_quantity': selectedValues['quantity'],
      'extra_items': selectedValues['extra_items'],
      'service_charge': selectedValues['service'],
      'previous_due': selectedValues['previous_due'],
      'payments_received': 0,
      'final_balance': selectedValues['total'],
      'status': 'unpaid',
    };
    try {
      await BillPdfService.generateAndShare(
        customer: customer,
        bill: bill,
        entries: const [],
        businessName: 'Atul Milk',
        businessPhone: '7030009085',
        businessAddress: 'Nashik',
        upiId: 'prashantsdeore15-1@oksbi',
        payeeName: 'Atul Milk',
        showDailyDeliveryDetails: false,
        invoiceTitle: 'CUSTOM MILK BILL',
      );
    } catch (error) {
      _message('Could not create custom bill PDF: $error');
    }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double get _milkTotal => _bills.fold<double>(0, (sum, bill) => sum + ((bill['milk_amount'] as num?)?.toDouble() ?? 0));
  double get _outstanding => _bills.fold<double>(0, (sum, bill) => sum + ((bill['final_balance'] as num?)?.toDouble() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'monthly-billing-custom-bill',
        onPressed: _sharing ? null : _createCustomBill,
        icon: const Icon(Icons.post_add),
        label: const Text('Custom bill'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _selectMonth,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('MMMM yyyy').format(_month)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search customer by name or mobile',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                      onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _summaryCard('Milk Billing', _money(_milkTotal), Icons.water_drop_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _summaryCard('Outstanding', _money(_outstanding), Icons.account_balance_wallet_outlined)),
                ]),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                    ? const Center(child: Text('No customers found for this month.'))
                    : _filteredBills.isEmpty
                        ? const Center(child: Text('No customers match your search.'))
                        : RefreshIndicator(
                            onRefresh: _generateBills,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredBills.length,
                              itemBuilder: (context, index) {
                                final bill = _filteredBills[index];
                                final name = _text(bill['name'], 'Customer');
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFE1F5FE),
                                      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () async {
                                      await Navigator.push(context, MaterialPageRoute<void>(
                                        builder: (_) => BillCustomerDetailScreen(bill: bill, onSharePdf: _shareBill),
                                      ));
                                      await _loadSavedBills();
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFE1F5FE), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 5),
        FittedBox(alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
      ]),
    );
  }
}

class _CustomBillDialog extends StatefulWidget {
  final List<Map<String, Object?>> customers;
  final Map<String, double> milkRates;

  const _CustomBillDialog({required this.customers, required this.milkRates});

  @override
  State<_CustomBillDialog> createState() => _CustomBillDialogState();
}

class _CustomBillDialogState extends State<_CustomBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _rate = TextEditingController();
  final _service = TextEditingController(text: '60');
  final _previousDue = TextEditingController(text: '0');
  late String _customerId;
  late String _milkType;
  List<Map<String, Object?>> _extraItems = [];

  static const _products = <(String, String, double, String)>[
    ('Cow Milk', 'cow_milk', 0, 'L'),
    ('Buffalo Milk', 'buffalo_milk', 0, 'L'),
    ('Fresh Milk', 'fresh_milk', 0, 'L'),
    ('Tak 500 ml', 'tak_500ml', 22, 'pack'),
    ('Dahi 100 gm', 'dahi_100', 16, 'pack'),
    ('Dahi 200 gm', 'dahi_200', 32, 'pack'),
    ('Dahi 500 gm', 'dahi_500', 43, 'pack'),
    ('Dahi 1 kg', 'dahi_1kg', 130, 'pack'),
  ];

  static const _types = <String, String>{
    'cow_milk': 'Cow milk',
    'buffalo_milk': 'Buffalo milk',
    'fresh_milk': 'Fresh milk',
  };

  String _rateKeyForCustomerType(Object? customerType) {
    switch (customerType?.toString()) {
      case 'standard':
      case 'buffalo':
      case 'buffalo_milk':
        return 'buffalo_milk';
      case 'full_cream':
      case 'fresh_milk':
        return 'fresh_milk';
      default:
        return 'cow_milk';
    }
  }

  @override
  void initState() {
    super.initState();
    final customer = widget.customers.first;
    _customerId = customer['id'].toString();
    _milkType = _rateKeyForCustomerType(customer['milk_type']);
    _rate.text = (widget.milkRates[_milkType] ?? 0).toStringAsFixed(2);
    for (final controller in [_quantity, _rate, _service, _previousDue]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _quantity.dispose();
    _rate.dispose();
    _service.dispose();
    _previousDue.dispose();
    super.dispose();
  }

  double _value(TextEditingController controller) => double.tryParse(controller.text.trim()) ?? 0;

  double get _itemsTotal => _extraItems.fold<double>(
    0,
    (sum, item) => sum + (item['total'] as double),
  );

  Future<void> _addItems() async {
    final initialQuantities = <String, String>{
      for (final item in _extraItems) item['key'] as String: (item['quantity'] as double).toString(),
    };
    final initiallySelected = initialQuantities.keys.toSet();
    final initialDahi = initiallySelected.firstWhere(
      (key) => key.startsWith('dahi_'),
      orElse: () => '',
    );
    final result = await showDialog<List<Map<String, Object?>>>(
      context: context,
      builder: (_) => _ExtraItemsPicker(
        products: _products,
        initialQuantities: initialQuantities,
        initiallySelected: initiallySelected,
        initialDahi: initialDahi.isEmpty ? null : initialDahi,
        itemRates: widget.milkRates,
      ),
    );
    if (result != null && mounted) setState(() => _extraItems = result);
  }

  String? _validate(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    return amount == null || !amount.isFinite || amount < 0 ? 'Enter a valid amount' : null;
  }

  Widget _numberField(TextEditingController controller, String label, {String? suffix}) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    validator: _validate,
  );

  @override
  Widget build(BuildContext context) {
    final milkAmount = _value(_quantity) * _value(_rate);
    final total = milkAmount + _itemsTotal + _value(_service) + _value(_previousDue);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF087E8B), Color(0xFF35B8A8)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.receipt_long, color: Colors.white)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create custom bill', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 3), Text('Enter milk details and review the total', style: TextStyle(color: Colors.white70)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                value: _customerId,
                decoration: const InputDecoration(labelText: 'Customer', prefixIcon: Icon(Icons.person_outline)),
                items: widget.customers.map((customer) => DropdownMenuItem(
                  value: customer['id'].toString(),
                  child: Text(customer['name']?.toString() ?? 'Customer'),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final customer = widget.customers.firstWhere((item) => item['id'].toString() == id);
                  setState(() {
                    _customerId = id;
                    _milkType = _rateKeyForCustomerType(customer['milk_type']);
                    _rate.text = (widget.milkRates[_milkType] ?? 0).toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 10,),
              DropdownButtonFormField<String>(
                value: _milkType,
                decoration: const InputDecoration(labelText: 'Milk type', prefixIcon: Icon(Icons.water_drop_outlined)),
                items: _types.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                onChanged: (type) {
                  if (type == null) return;
                  setState(() {
                    _milkType = type;
                    _rate.text = (widget.milkRates[type] ?? 0).toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 8,),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addItems,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('Add item'),
                ),
              ),
              if (_extraItems.isNotEmpty) ...[
                const SizedBox(height: 4),
                ..._extraItems.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  elevation: 0,
                  color: const Color(0xFFF5FAFA),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: const Icon(Icons.shopping_basket_outlined, color: Color(0xFF087E8B)),
                    title: Text(item['label'] as String),
                    subtitle: Text('${(item['quantity'] as double).toStringAsFixed(2)} ${item['unit']} × ₹${(item['price'] as double).toStringAsFixed(2)}'),
                    trailing: Text('₹${(item['total'] as double).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                )),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _numberField(_quantity, 'Milk quantity', suffix: 'L')),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_rate, 'Price per litre', suffix: '₹/L')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _numberField(_service, 'Service charge', suffix: '₹')),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_previousDue, 'Previous due', suffix: '₹')),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFEAF7F5), borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _totalRow('Milk amount', '${milkAmount.toStringAsFixed(2)}'),
                  if (_extraItems.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _totalRow('Extra items', '₹${_itemsTotal.toStringAsFixed(2)}'),
                  ],
                  const SizedBox(height: 7),
                  _totalRow('Service + previous due', '${(_value(_service) + _value(_previousDue)).toStringAsFixed(2)}'),
                  const Divider(height: 20),
                  _totalRow('Total bill', '₹${total.toStringAsFixed(2)}', bold: true),
                ]),
              ),
            ])),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 18), child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FilledButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                final qty = _value(_quantity);
                final rate = _value(_rate);
                final service = _value(_service);
                final due = _value(_previousDue);
                Navigator.pop(context, <String, Object?>{
                  'customer_id': _customerId,
                  'quantity': qty,
                  'rate': rate,
                  'milk_type': _milkType,
                  'extra_items': _extraItems,
                  'extra_items_amount': _itemsTotal,
                  'service': service,
                  'previous_due': due,
                  'milk_amount': qty * rate,
                  'total': qty * rate + _itemsTotal + service + due,
                });
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Create PDF'),
            )),
          ])),
        ]),
      ),
    );
  }

  Widget _totalRow(String label, String amount, {bool bold = false}) => Row(children: [
    Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
    Text(amount, style: TextStyle(fontWeight: FontWeight.bold, fontSize: bold ? 18 : 14)),
  ]);
}

class _ExtraItemsPicker extends StatefulWidget {
  final List<(String, String, double, String)> products;
  final Map<String, String> initialQuantities;
  final Set<String> initiallySelected;
  final String? initialDahi;
  final Map<String, double> itemRates;

  const _ExtraItemsPicker({
    required this.products,
    required this.initialQuantities,
    required this.initiallySelected,
    required this.initialDahi,
    required this.itemRates,
  });

  @override
  State<_ExtraItemsPicker> createState() => _ExtraItemsPickerState();
}

class _ExtraItemsPickerState extends State<_ExtraItemsPicker> {
  late final Set<String> _selected;
  late final Map<String, String> _quantities;
  String? _selectedDahi;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
    _quantities = Map<String, String>.from(widget.initialQuantities);
    _selectedDahi = widget.initialDahi;
  }

  void _save() {
    final items = <Map<String, Object?>>[];
    for (final (label, key, listedPrice, unit) in widget.products) {
      final isDahi = key.startsWith('dahi_');
      if (isDahi ? key != _selectedDahi : !_selected.contains(key)) continue;
      final quantity = double.tryParse(_quantities[key] ?? '') ?? 0;
      if (!quantity.isFinite || quantity <= 0) {
        setState(() => _error = 'Enter a quantity greater than zero for $label.');
        return;
      }
      final price = listedPrice == 0 ? (widget.itemRates[key] ?? 0) : listedPrice;
      items.add({
        'label': label,
        'key': key,
        'quantity': quantity,
        'unit': unit,
        'price': price,
        'total': quantity * price,
      });
    }
    Navigator.of(context).pop(items);
  }

  Widget _quantityField(String key, String label, String unit) => Padding(
    padding: const EdgeInsets.only(left: 54, right: 12, bottom: 8),
    child: TextFormField(
      key: ValueKey('quantity-$key'),
      initialValue: _quantities[key] ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(isDense: true, labelText: '$label quantity', suffixText: unit),
      onChanged: (value) => setState(() {
        _quantities[key] = value;
        _error = null;
      }),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add extra items'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        ...widget.products.where((product) => !product.$2.startsWith('dahi_')).map((product) {
          final (label, key, listedPrice, unit) = product;
          final price = listedPrice == 0 ? (widget.itemRates[key] ?? 0) : listedPrice;
          return Column(children: [
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text('₹${price.toStringAsFixed(2)} / $unit'),
              value: _selected.contains(key),
              onChanged: (checked) => setState(() {
                _error = null;
                if (checked == true) {
                  _selected.add(key);
                  _quantities.putIfAbsent(key, () => '');
                } else {
                  _selected.remove(key);
                }
              }),
            ),
            if (_selected.contains(key)) _quantityField(key, label, unit),
          ]);
        }),
        const Divider(),
        const Align(alignment: Alignment.centerLeft, child: Text('Dahi size', style: TextStyle(fontWeight: FontWeight.w600))),
        ...widget.products.where((product) => product.$2.startsWith('dahi_')).map((product) {
          final (label, key, price, unit) = product;
          return Column(children: [
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text('₹${price.toStringAsFixed(2)} / $unit'),
              value: key,
              groupValue: _selectedDahi,
              onChanged: (value) => setState(() {
                _error = null;
                _selectedDahi = value;
                if (value != null) _quantities.putIfAbsent(value, () => '');
              }),
            ),
            if (_selectedDahi == key) _quantityField(key, label, unit),
          ]);
        }),
      ])),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _save, child: const Text('Add selected items')),
    ],
  );
}
