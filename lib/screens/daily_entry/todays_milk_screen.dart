import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_data_service.dart';

class TodaysMilkScreen extends StatefulWidget {
  const TodaysMilkScreen({super.key});

  @override
  State<TodaysMilkScreen> createState() => _TodaysMilkScreenState();
}

class _TodaysMilkScreenState extends State<TodaysMilkScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;
  double _cowMilk = 0;
  double _standardMilk = 0;
  double _freshCreamMilk = 0;
  double _dahiPacks = 0;
  double _takPacks = 0;
  final Map<String, double> _dahiSizes = {};

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _loadBreakdown();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
    await _loadBreakdown();
  }

  Future<void> _loadBreakdown() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = FirestoreDataService.instance;
      final customers = await service.getCustomers(activeOnly: false);
      final customerById = {
        for (final customer in customers)
          customer['id'].toString(): customer,
      };
      final entries = await service.getMilkEntries(_dateKey);

      var cowMilk = 0.0;
      var standardMilk = 0.0;
      var freshCreamMilk = 0.0;
      for (final entry in entries) {
        if (entry['delivered'] != true && entry['delivered'] != 1) continue;
        final customer = customerById[entry['customer_id']?.toString()];
        final type = customer?['milk_type']?.toString() ?? 'cow';
        final quantity = (entry['quantity'] as num?)?.toDouble() ?? 0;
        switch (type) {
          case 'standard':
          case 'buffalo':
            standardMilk += quantity;
            break;
          case 'full_cream':
          case 'fresh_milk':
            freshCreamMilk += quantity;
            break;
          default:
            cowMilk += quantity;
            break;
        }
      }

      final productRows = await Future.wait(
        customers.map((customer) => service.getCustomerDailyProducts(
              customer['id'].toString(),
              _dateKey,
            )),
      );
      var dahiPacks = 0.0;
      var takPacks = 0.0;
      final dahiSizes = <String, double>{};
      for (final row in productRows.expand((rows) => rows)) {
        final name = row['product_name']?.toString() ?? '';
        final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
        switch (name) {
          case 'cow_milk':
            cowMilk += quantity;
            break;
          case 'buffalo_milk':
            standardMilk += quantity;
            break;
          case 'fresh_milk':
            freshCreamMilk += quantity;
            break;
          case 'tak_500ml':
            takPacks += quantity;
            break;
          case 'dahi_100':
          case 'dahi_200':
          case 'dahi_500':
          case 'dahi_1kg':
            dahiPacks += quantity;
            dahiSizes[name] = (dahiSizes[name] ?? 0) + quantity;
            break;
        }
      }

      if (!mounted) return;
      setState(() {
        _cowMilk = cowMilk;
        _standardMilk = standardMilk;
        _freshCreamMilk = freshCreamMilk;
        _dahiPacks = dahiPacks;
        _takPacks = takPacks;
        _dahiSizes
          ..clear()
          ..addAll(dahiSizes);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load today\'s deliveries: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMilk = _cowMilk + _standardMilk + _freshCreamMilk;
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Milk")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadBreakdown,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBreakdown,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('EEEE, dd MMMM yyyy')
                                  .format(_selectedDate),
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _selectDate,
                            icon: const Icon(Icons.calendar_month),
                            label: const Text('Filter date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _totalCard(totalMilk),
                      const SizedBox(height: 20),
                      const Text(
                        'Delivered breakdown',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _quantityCard('Cow Milk', _cowMilk, 'L', Icons.water_drop_outlined),
                      _quantityCard('Standard Milk', _standardMilk, 'L', Icons.water_drop_outlined),
                      _quantityCard('Fresh Cream Milk', _freshCreamMilk, 'L', Icons.water_drop_outlined),
                      const SizedBox(height: 8),
                      _quantityCard(
                        'Dahi',
                        _dahiPacks,
                        'packs',
                        Icons.inventory_2_outlined,
                        detail: _formatDahiSizes(),
                      ),
                      _quantityCard('Tak', _takPacks, 'packs', Icons.local_drink_outlined),
                    ],
                  ),
                ),
    );
  }

  Widget _totalCard(double liters) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.water_drop_outlined, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Total milk delivered',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${liters.toStringAsFixed(2)} L',
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _quantityCard(
    String title,
    double quantity,
    String unit,
    IconData icon, {
    String? detail,
  }) {
    final amount = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1EFF6)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE1F5FE),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        title: Text(title),
        subtitle: detail == null || detail.isEmpty ? null : Text(detail),
        trailing: Text(
          '$amount $unit',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  String _formatDahiSizes() {
    const labels = {
      'dahi_100': '100 g',
      'dahi_200': '200 g',
      'dahi_500': '500 g',
      'dahi_1kg': '1 kg',
    };
    return labels.entries
        .where((entry) => (_dahiSizes[entry.key] ?? 0) > 0)
        .map((entry) {
          final quantity = _dahiSizes[entry.key]!;
          final amount = quantity == quantity.roundToDouble()
              ? quantity.toStringAsFixed(0)
              : quantity.toStringAsFixed(2);
          return '${entry.value}: $amount';
        })
        .join(' | ');
  }
}
