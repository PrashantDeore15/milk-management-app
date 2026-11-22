import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_data_service.dart';
import '../../services/user_session.dart';

class BillCustomerDetailScreen extends StatefulWidget {
  final Map<String, Object?> bill;
  final Future<void> Function(Map<String, Object?> bill) onSharePdf;

  const BillCustomerDetailScreen({
    super.key,
    required this.bill,
    required this.onSharePdf,
  });

  @override
  State<BillCustomerDetailScreen> createState() => _BillCustomerDetailScreenState();
}

class _BillCustomerDetailScreenState extends State<BillCustomerDetailScreen> {
  bool _loading = true;
  bool _sharing = false;
  List<Map<String, Object?>> _entries = [];
  List<Map<String, Object?>> _extraEntries = [];
  late Map<String, Object?> _currentBill;

  String get _month => widget.bill['billing_month']?.toString() ?? '';
  String get _customerName => widget.bill['name']?.toString() ?? 'Customer';

  @override
  void initState() {
    super.initState();
    _currentBill = Map<String, Object?>.from(widget.bill);
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final parts = _month.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final start = DateFormat('yyyy-MM-dd').format(DateTime(year, month));
      final end = DateFormat('yyyy-MM-dd').format(DateTime(year, month + 1));
      final service = FirestoreDataService.instance;
      final customerId = widget.bill['customer_id'].toString();
      final rows = await service.getMilkEntriesForPeriod(customerId: customerId, startDate: start, endDate: end);
      rows.sort((a, b) => (b['entry_date'] ?? '').toString().compareTo((a['entry_date'] ?? '').toString()));
      final extraRows = await service.getDailyProductsForPeriod(customerId: customerId, startDate: start, endDate: end);
      extraRows.sort((a, b) => (b['entry_date'] ?? '').toString().compareTo((a['entry_date'] ?? '').toString()));
      final paymentRows = await service.getPaymentsForPeriod(customerId: customerId, startDate: start, endDate: end);
      final milkAmount = rows.fold<double>(
        0,
        (sum, entry) => sum + (entry['quantity'] as num).toDouble() * (entry['rate'] as num).toDouble(),
      ) + extraRows.fold<double>(0, (sum, entry) => sum + (entry['quantity'] as num).toDouble() * (entry['unit_price'] as num).toDouble());
      final serviceCharge = (_currentBill['service_charge'] as num?)?.toDouble() ?? 60;
      final previousDue = (_currentBill['previous_due'] as num?)?.toDouble() ?? 0;
      final paymentsReceived = paymentRows.fold<double>(0, (sum, payment) => sum + ((payment['amount'] as num?)?.toDouble() ?? 0));
      final calculatedBalance = previousDue + milkAmount + serviceCharge - paymentsReceived;
      final finalBalance = calculatedBalance > 0 ? calculatedBalance : 0.0;
      final updatedBill = <String, Object?>{
        ..._currentBill,
        'milk_amount': milkAmount,
        'service_charge': serviceCharge,
        'payments_received': paymentsReceived,
        'final_balance': finalBalance,
        'status': calculatedBalance <= 0 ? 'paid' : 'unpaid',
      };
      if (UserSession.can('bills', 'edit')) {
        await service.updateBill(
          widget.bill['id'].toString(),
          {
            'milk_amount': milkAmount,
            'service_charge': serviceCharge,
            'payments_received': paymentsReceived,
            'final_balance': finalBalance,
            'status': calculatedBalance <= 0 ? 'paid' : 'unpaid',
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _extraEntries = extraRows;
        _currentBill = updatedBill;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _liters => _entries.fold<double>(0, (sum, entry) => sum + (entry['quantity'] as num).toDouble());

  String _money(Object? value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(amount);
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await widget.onSharePdf(_currentBill);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.tryParse('$_month-01') ?? DateTime.now());
    final serviceCharge = _currentBill['service_charge'] ?? 60;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Bill')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 32),
                      const SizedBox(height: 12),
                      Text(_customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 21)),
                      const SizedBox(height: 4),
                      Text('$monthLabel bill', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _statCard('Delivered days', '${_entries.length}', Icons.calendar_month_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Milk delivered', '${_liters.toStringAsFixed(2)} L', Icons.water_drop_outlined)),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE1EFF6))),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _billRow('Milk Amount', _money(_currentBill['milk_amount'])),
                        _billRow('Service Charge', _money(serviceCharge)),
                        _billRow('Previous Due', _money(_currentBill['previous_due'])),
                        _billRow('Payments Received', _money(_currentBill['payments_received'])),
                        const Divider(height: 22),
                        _billRow('Amount Due', _money(_currentBill['final_balance']), bold: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('$monthLabel milk entries', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No milk deliveries recorded for this month.')))
                else
                  ..._entries.map((entry) {
                    final quantity = (entry['quantity'] as num).toDouble();
                    final rate = (entry['rate'] as num).toDouble();
                    final date = DateTime.tryParse(entry['entry_date'] as String);
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE1EFF6))),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFE1F5FE), child: Icon(Icons.local_drink_outlined, color: AppTheme.primaryColor)),
                        title: Text(date == null ? entry['entry_date'].toString() : DateFormat('EEE, dd MMM').format(date)),
                        subtitle: Text('${quantity.toStringAsFixed(2)} L × ${_money(rate)}/L'),
                        trailing: Text(_money(quantity * rate), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    );
                  }),
                ..._extraEntries.map((entry) {
                  final date = DateTime.tryParse(entry['entry_date'] as String);
                  final label = (entry['product_name'] as String).replaceAll('_', ' ');
                  final qty = (entry['quantity'] as num).toDouble();
                  final price = (entry['unit_price'] as num).toDouble();
                  return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.shopping_basket_outlined)),
                    title: Text('${label[0].toUpperCase()}${label.substring(1)} · ${date == null ? entry['entry_date'] : DateFormat('EEE, dd MMM').format(date)}'),
                    subtitle: Text('$qty ${entry['unit']} × ${_money(price)}'),
                    trailing: Text(_money(qty * price)),
                  ));
                }),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.share_rounded),
                    label: Text(_sharing ? 'Preparing PDF...' : 'Share Bill PDF'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE1EFF6))),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppTheme.primaryColor),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _billRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 17 : 14)),
      ]),
    );
  }
}
