import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:milk_management_system/core/theme/app_theme.dart';
import 'package:milk_management_system/services/firestore_data_service.dart';

enum HomeMetric { monthlyBilling, pendingAmount }

class HomeMetricDetailScreen extends StatefulWidget {
  final HomeMetric metric;

  const HomeMetricDetailScreen({super.key, required this.metric});

  @override
  State<HomeMetricDetailScreen> createState() =>
      _HomeMetricDetailScreenState();
}

class _HomeMetricDetailScreenState extends State<HomeMetricDetailScreen> {
  static const double _serviceCharge = 60;

  bool _loading = true;
  String? _error;
  List<_CustomerBillingDetail> _details = [];

  bool get _isPending => widget.metric == HomeMetric.pendingAmount;
  String get _title => _isPending ? 'Pending Amount Details' : 'Monthly Billing Details';
  double get _total => _details.fold<double>(
        0,
        (sum, item) => sum + (_isPending ? item.pendingAmount : item.monthlyTotal),
      );

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = FirestoreDataService.instance;
      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);
      final startDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month));
      final endDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month + 1));
      final customers = await service.getCustomers();

      final details = await Future.wait(customers.map((customer) async {
        final customerId = customer['id'].toString();
        final results = await Future.wait([
          service.getMilkEntriesForPeriod(
            customerId: customerId,
            startDate: startDate,
            endDate: endDate,
          ),
          service.getDailyProductsForPeriod(
            customerId: customerId,
            startDate: startDate,
            endDate: endDate,
          ),
          service.getPreviousBills(customerId, monthKey),
          service.getPaymentsForPeriod(
            customerId: customerId,
            startDate: startDate,
            endDate: endDate,
          ),
        ]);
        final milkEntries = results[0] as List<Map<String, dynamic>>;
        final products = results[1] as List<Map<String, dynamic>>;
        final previousBills = results[2] as List<Map<String, dynamic>>;
        final payments = results[3] as List<Map<String, dynamic>>;

        final milkAmount = milkEntries.fold<double>(
              0,
              (sum, row) => sum +
                  _number(row['quantity']) * _number(row['rate']),
            ) +
            products.fold<double>(
              0,
              (sum, row) => sum +
                  _number(row['quantity']) * _number(row['unit_price']),
            );
        final previousDue = previousBills.isEmpty
            ? 0.0
            : service.unpaidPreviousDue(previousBills.first);
        final paymentsReceived = payments.fold<double>(
          0,
          (sum, row) => sum + _number(row['amount']),
        );
        final rawBalance =
            milkAmount + _serviceCharge + previousDue - paymentsReceived;

        return _CustomerBillingDetail(
          name: customer['name']?.toString() ?? 'Customer',
          milkAmount: milkAmount,
          serviceCharge: _serviceCharge,
          previousDue: previousDue,
          paymentsReceived: paymentsReceived,
          pendingAmount: rawBalance > 0 ? rawBalance : 0,
        );
      }));

      details.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (_isPending) {
        details.removeWhere((item) => item.pendingAmount <= 0);
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load billing details: $error';
        _loading = false;
      });
    }
  }

  double _number(Object? value) => (value as num?)?.toDouble() ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
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
                          onPressed: _loadDetails,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDetails,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(month, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 12),
                      _totalCard(),
                      const SizedBox(height: 20),
                      Text(
                        _isPending ? 'Customers with balance due' : 'Customer breakdown',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (_details.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                _isPending
                                    ? 'No pending amounts for this month.'
                                    : 'No billing details found for this month.',
                              ),
                            ),
                          ),
                        )
                      else
                        ..._details.map(_customerCard),
                    ],
                  ),
                ),
    );
  }

  Widget _totalCard() {
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
            child: Icon(Icons.receipt_long_outlined, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isPending ? 'Total pending' : 'Total monthly billing',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _money(_total),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(_CustomerBillingDetail detail) {
    final amount = _isPending ? detail.pendingAmount : detail.monthlyTotal;
    final subtitle = _isPending
        ? 'Current bill ${_money(detail.currentTotal)} · Previous due ${_money(detail.previousDue)} · Payments ${_money(detail.paymentsReceived)}'
        : 'Milk and products ${_money(detail.milkAmount)} · Service charge ${_money(detail.serviceCharge)}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1EFF6)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE1F5FE),
          child: Text(
            detail.name.isEmpty ? '?' : detail.name[0].toUpperCase(),
            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(detail.name),
        subtitle: Text(subtitle),
        isThreeLine: _isPending,
        trailing: Text(
          _money(amount),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CustomerBillingDetail {
  final String name;
  final double milkAmount;
  final double serviceCharge;
  final double previousDue;
  final double paymentsReceived;
  final double pendingAmount;

  const _CustomerBillingDetail({
    required this.name,
    required this.milkAmount,
    required this.serviceCharge,
    required this.previousDue,
    required this.paymentsReceived,
    required this.pendingAmount,
  });

  double get currentTotal => milkAmount + serviceCharge;
  double get monthlyTotal => currentTotal;
}
