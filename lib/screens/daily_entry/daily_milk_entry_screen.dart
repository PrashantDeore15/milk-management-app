
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/customer_models.dart';
import '../../services/customer_cache_service.dart';
import '../database/database_helper.dart';
import 'customer_monthly_summary_screen.dart';


class DailyMilkEntryScreen extends StatefulWidget {
  const DailyMilkEntryScreen({super.key});

  @override
  State<DailyMilkEntryScreen> createState() =>
      _DailyMilkEntryScreenState();
}

class _DailyMilkEntryScreenState
    extends State<DailyMilkEntryScreen> {
  DateTime _selectedDate = DateTime.now();

  List<CustomerModel> _customers = [];
  final Map<String, TextEditingController> _quantityControllers = {};
  final Map<String, bool> _delivered = {};

  bool _loading = true;
  bool _saving = false;

  String get _dateKey =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);

    try {
      await CustomerCacheService.refresh();
      final rows = await DatabaseHelper.instance.getCustomers();

      final customers = rows
          .map((row) => CustomerModel.fromMap(row))
          .toList();

      final entries =
      await DatabaseHelper.instance.getMilkEntries(_dateKey);

      final entryMap = {
        for (final entry in entries)
          entry['customer_id'] as String: entry,
      };

      for (final controller in _quantityControllers.values) {
        controller.dispose();
      }

      _quantityControllers.clear();
      _delivered.clear();

      for (final customer in customers) {
        final existing = entryMap[customer.id];

        _quantityControllers[customer.id] =
            TextEditingController(
              text: existing == null
                  ? customer.morningQuantity.toString()
                  : (existing['quantity'] as num).toString(),
            );

        _delivered[customer.id] = existing == null
            ? false
            : (existing['delivered'] as int) == 1;
      }

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data load error: $e')),
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) return;

    setState(() => _selectedDate = picked);
    await _loadData();
  }

  Future<void> _showMoreProducts(CustomerModel customer) async {
    final existing = await DatabaseHelper.instance.getCustomerDailyProducts(customer.id, _dateKey);
    if (!mounted) return;
    const products = <(String, String, double, String)>[
      ('Cow Milk', 'cow_milk', 0, 'L'), ('Buffalo Milk', 'buffalo_milk', 0, 'L'),
      ('Fresh Milk', 'fresh_milk', 0, 'L'), ('Tak 500 ml', 'tak_500ml', 22, 'pack'),
      ('Dahi 100 gm', 'dahi_100', 16, 'pack'), ('Dahi 200 gm', 'dahi_200', 32, 'pack'),
      ('Dahi 500 gm', 'dahi_500', 43, 'pack'), ('Dahi 1 kg', 'dahi_1kg', 130, 'pack'),
    ];
    final savedByKey = {for (final row in existing) row['product_name'] as String: row};
    final quantities = <String, TextEditingController>{};
    for (final (label, key, _, unit) in products) {
      final row = savedByKey[key];
      quantities[key] = TextEditingController(text: row == null ? '' : (row['quantity'] as num).toString());
    }
    final selected = <String>{for (final item in products) if (savedByKey.containsKey(item.$2)) item.$2};
    String? selectedDahi = ['dahi_100', 'dahi_200', 'dahi_500', 'dahi_1kg'].firstWhere((key) => selected.contains(key), orElse: () => '');
    if (selectedDahi.isEmpty) selectedDahi = null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
        title: Text('Extra items · ${customer.name}'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...products.where((p) => !p.$2.startsWith('dahi_')).map((product) {
            final (label, key, _, unit) = product;
            return Column(children: [
              CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(label), value: selected.contains(key), onChanged: (checked) => refreshDialog(() { if (checked == true) { selected.add(key); } else { selected.remove(key); } })),
              if (selected.contains(key)) Padding(padding: const EdgeInsets.only(left: 16, bottom: 8), child: TextField(controller: quantities[key], autofocus: false, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(isDense: true, labelText: 'Quantity', suffixText: unit))),
            ]);
          }),
          const Divider(),
          const Align(alignment: Alignment.centerLeft, child: Text('Dahi size', style: TextStyle(fontWeight: FontWeight.w600))),
          ...products.where((p) => p.$2.startsWith('dahi_')).map((product) {
            final (label, key, _, unit) = product;
            return RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, title: Text(label), value: key, groupValue: selectedDahi, onChanged: (value) => refreshDialog(() => selectedDahi = value));
          }),
          if (selectedDahi != null) TextField(controller: quantities[selectedDahi], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(isDense: true, labelText: 'Dahi quantity', suffixText: 'pack')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save items'))],
      )),
    );
    if (saved == true) {
      final rows = <Map<String, Object?>>[];
      for (final (label, key, listedPrice, unit) in products) {
        if (key.startsWith('dahi_') ? key != selectedDahi : !selected.contains(key)) continue;
        final qty = double.tryParse(quantities[key]!.text) ?? 0;
        final price = listedPrice == 0 ? customer.rate : listedPrice;
        if (qty <= 0 || !qty.isFinite) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter a valid quantity for $label.')));
          for (final c in quantities.values) { c.dispose(); }
          return;
        }
        rows.add({'id': const Uuid().v4(), 'customer_id': customer.id, 'entry_date': _dateKey, 'product_name': key, 'quantity': qty, 'unit': unit, 'unit_price': price});
      }
      await DatabaseHelper.instance.saveCustomerDailyProducts(rows, customer.id, _dateKey);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Extra items saved for this customer.')));
    }
    for (final c in quantities.values) { c.dispose(); }
  }

  double get _totalMilk {
    double total = 0;

    for (final customer in _customers) {
      if (_delivered[customer.id] != true) continue;

      final quantity = double.tryParse(
        _quantityControllers[customer.id]?.text ?? '',
      ) ??
          0;

      if (quantity.isFinite && quantity > 0) {
        total += quantity;
      }
    }

    return total;
  }

  int get _deliveredCount =>
      _customers.where((c) => _delivered[c.id] == true).length;

  Future<void> _saveEntries() async {
    if (_saving) return;

    for (final customer in _customers) {
      final controller = _quantityControllers[customer.id];
      final value = double.tryParse(controller?.text ?? '');

      if (value == null ||
          !value.isFinite ||
          value < 0 ||
          value > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${customer.name}: दूधाचे प्रमाण 0 ते 100 लिटरमध्ये भरा.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      for (final customer in _customers) {
        final delivered = _delivered[customer.id] ?? false;
        final quantity = delivered
            ? double.parse(
          _quantityControllers[customer.id]!.text,
        )
            : 0.0;

        await DatabaseHelper.instance.saveMilkEntry({
          'id': const Uuid().v4(),
          'customer_id': customer.id,
          'entry_date': _dateKey,
          'quantity': quantity,
          'delivered': delivered ? 1 : 0,
          'rate': customer.rate,
          'notes': delivered ? '' : 'Not delivered',
          'synced': 0,
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('आजच्या दूध नोंदी सेव्ह झाल्या!'),
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('dd MMM yyyy')
        .format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Milk Entry'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(dateText),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        'Customers',
                        '${_customers.length}',
                        Icons.people_outline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _summaryCard(
                        'Delivered',
                        '$_deliveredCount',
                        Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _summaryCard(
                        'Total Milk',
                        '${_totalMilk.toStringAsFixed(2)} L',
                        Icons.water_drop_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _customers.isEmpty
                ? const Center(
              child: Text(
                'No active customers. Add customers first.',
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                12, 8, 12, 16,
              ),
              itemCount: _customers.length,
              itemBuilder: (context, index) {
                final customer = _customers[index];
                final isDelivered =
                    _delivered[customer.id] ?? true;

                return Card(
                  margin: const EdgeInsets.only(
                    bottom: 10,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CustomerMonthlySummaryScreen(customer: customer),
                        ),
                      );
                    },
                    child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              child: Text(
                                customer.name.isNotEmpty
                                    ? customer.name[0]
                                    .toUpperCase()
                                    : '?',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style: const TextStyle(
                                      fontWeight:
                                      FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${_milkLabel(customer.milkType)}'
                                        ' • ₹${customer.rate}/L',
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showMoreProducts(customer),
                              child: const Text('More'),
                            ),
                            FilledButton.tonal(
                              onPressed: () {
                                setState(() {
                                  _delivered[customer.id] =
                                      !isDelivered;
                                });
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: isDelivered ? const Color(0xFFE1F5FE) : AppTheme.primaryColor,
                                foregroundColor: isDelivered ? AppTheme.primaryColor : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              child: Text(isDelivered ? 'Delivered ✓' : 'Mark delivered'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Quantity (Liters)',
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller:
                                _quantityControllers[
                                customer.id],
                                enabled: isDelivered,
                                keyboardType:
                                const TextInputType
                                    .numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) {
                                  setState(() {});
                                },
                                decoration:
                                const InputDecoration(
                                  isDense: true,
                                  suffixText: 'L',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  _saving ? null : _saveEntries,
                  icon: _saving
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : 'Save Daily Entries',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
      String title,
      String value,
      IconData icon,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE1F5FE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primaryColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _milkLabel(String type) {
    switch (type) {
      case 'cow':
        return 'Cow Milk';
      case 'full_cream':
        return 'Full Cream Milk';
      default:
        return 'Standard Milk';
    }
  }
}
