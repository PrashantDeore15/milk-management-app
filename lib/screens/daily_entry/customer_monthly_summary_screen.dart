import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/customer_models.dart';
import '../database/database_helper.dart';

class CustomerMonthlySummaryScreen extends StatefulWidget {
  final CustomerModel customer;

  const CustomerMonthlySummaryScreen({super.key, required this.customer});

  @override
  State<CustomerMonthlySummaryScreen> createState() => _CustomerMonthlySummaryScreenState();
}

class _CustomerMonthlySummaryScreenState extends State<CustomerMonthlySummaryScreen> {
  bool _loading = true;
  List<Map<String, Object?>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    final now = DateTime.now();
    final start = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month));
    final end = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, now.day));
    final db = await DatabaseHelper.instance.database;
    final entries = await db.query(
      'milk_entries',
      where: 'customer_id = ? AND entry_date >= ? AND entry_date <= ? AND delivered = 1',
      whereArgs: [widget.customer.id, start, end],
      orderBy: 'entry_date DESC',
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  double get _totalLiters => _entries.fold<double>(0, (sum, entry) => sum + (entry['quantity'] as num).toDouble());
  double get _bill => _entries.fold<double>(0, (sum, entry) => sum + (entry['quantity'] as num).toDouble() * (entry['rate'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Monthly Summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMonth,
              child: ListView(
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
                        CircleAvatar(backgroundColor: Colors.white, child: Text(widget.customer.name.isEmpty ? '?' : widget.customer.name[0].toUpperCase(), style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold))),
                        const SizedBox(height: 14),
                        Text(widget.customer.name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('$month · ${widget.customer.mobile}', style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _statCard('Delivered days', '${_entries.length}', Icons.check_circle_outline)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('Milk delivered', '${_totalLiters.toStringAsFixed(2)} L', Icons.water_drop_outlined)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: const Color(0xFFE1F5FE),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined, color: AppTheme.primaryColor, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Bill so far this month', style: TextStyle(fontWeight: FontWeight.w600))),
                          Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(_bill), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('$month delivery history', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  if (_entries.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No delivered milk recorded this month yet.'))))
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
                          title: Text(date == null ? entry['entry_date'] as String : DateFormat('EEE, dd MMM').format(date)),
                          subtitle: Text('${quantity.toStringAsFixed(2)} L × ₹${rate.toStringAsFixed(2)}/L'),
                          trailing: Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(quantity * rate), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE1EFF6))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppTheme.primaryColor),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
      ),
    );
  }
}
