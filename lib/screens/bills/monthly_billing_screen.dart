import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/theme/app_theme.dart';
import '../../services/bill_pdf_service.dart';
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
        payeeName: 'Atul Milk',
      );
    } catch (error) {
      _message('Could not share bill PDF: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
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
