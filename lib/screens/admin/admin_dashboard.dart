import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_data_service.dart';
import 'milk_rates_screen.dart';
import '../bills/monthly_billing_screen.dart';
import '../customers/customer_list_screen.dart';
import '../daily_entry/daily_milk_entry_screen.dart';
import '../payments/payment_collection_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  static const _titles = ['Milk Management', 'Customers', 'Payments', 'Bills'];

  List<Widget> get _pages => [
    const _HomePage(),
    const CustomerListScreen(),
    const PaymentCollectionScreen(),
    const MonthlyBillingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people_rounded), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments_rounded), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Bills'),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.water_drop_rounded, color: AppTheme.primaryColor, size: 30)),
                  SizedBox(height: 14),
                  Text('Milk Management', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 4),
                  Text('Fresh service, every day', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _drawerItem(Icons.home_outlined, 'Home', 0),
            _drawerItem(Icons.people_outline, 'Customers', 1),
            _drawerItem(Icons.payments_outlined, 'Payments', 2),
            _drawerItem(Icons.receipt_long_outlined, 'Bills', 3),
            ListTile(
              leading: const Icon(Icons.price_change_outlined, color: AppTheme.primaryColor),
              title: const Text('Milk Rates'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              onTap: () {
                Navigator.pop(context);
                _openMilkRates();
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Milk Management System', style: TextStyle(color: Colors.black45, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMilkRates() async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MilkRatesScreen()));
    if (mounted) setState(() {});
  }

  Widget _drawerItem(IconData icon, String label, int index) {
    return ListTile(
      leading: Icon(icon, color: _selectedIndex == index ? AppTheme.primaryColor : Colors.black54),
      title: Text(label, style: TextStyle(fontWeight: _selectedIndex == index ? FontWeight.w600 : FontWeight.normal)),
      selected: _selectedIndex == index,
      selectedTileColor: const Color(0xFFE1F5FE),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  bool _loadingStats = true;
  int _customerCount = 0;
  double _todayMilk = 0;
  double _monthlyBilling = 0;
  double _pendingAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final service = FirestoreDataService.instance;
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final monthStart = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month));
      final nextMonth = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month + 1));
      final billingMonth = DateFormat('yyyy-MM').format(now);

      final customers = await service.getCustomers();
      final todayEntries = await service.getMilkEntries(today);
      final todayMilk = todayEntries.where((row) => row['delivered'] == true || row['delivered'] == 1).fold<double>(0, (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0));
      // Query each active customer because Firestore entries are partitioned by customer.
      var monthlyMilk = 0.0;
      var pending = 0.0;
      for (final customer in customers) {
        final id = customer['id'].toString();
        final entries = await service.getMilkEntriesForPeriod(customerId: id, startDate: monthStart, endDate: nextMonth);
        monthlyMilk += entries.fold<double>(0, (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0) * ((row['rate'] as num?)?.toDouble() ?? 0));
        final previous = await service.getPreviousBills(id, billingMonth);
        final payments = await service.getPaymentsForPeriod(customerId: id, startDate: monthStart, endDate: nextMonth);
        final extras = await service.getDailyProductsForPeriod(customerId: id, startDate: monthStart, endDate: nextMonth);
        final previousDue = previous.isEmpty ? 0.0 : (previous.first['final_balance'] as num?)?.toDouble() ?? 0;
        final extraAmount = extras.fold<double>(0, (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0) * ((row['unit_price'] as num?)?.toDouble() ?? 0));
        final milkAmount = entries.fold<double>(0, (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0) * ((row['rate'] as num?)?.toDouble() ?? 0)) + extraAmount;
        monthlyMilk += extraAmount;
        final received = payments.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
        final balance = previousDue + milkAmount + 60 - received;
        if (balance > 0) pending += balance;
      }

      if (!mounted) return;
      setState(() {
        _customerCount = customers.length;
        _todayMilk = todayMilk;
        _monthlyBilling = monthlyMilk + customers.length * 60;
        _pendingAmount = pending;
        _loadingStats = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: .22), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good day! 👋', style: TextStyle(color: Colors.white, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('Your business at a glance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 21)),
                  SizedBox(height: 18),
                  Row(children: [Icon(Icons.wb_sunny_outlined, color: Colors.white), SizedBox(width: 8), Text('Keep your daily records up to date', style: TextStyle(color: Colors.white))]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(title: 'Customers', value: _loadingStats ? '...' : '$_customerCount', icon: Icons.people_alt_outlined),
                _SummaryCard(title: "Today's Milk", value: _loadingStats ? '...' : '${_todayMilk.toStringAsFixed(2)} L', icon: Icons.water_drop_outlined),
                _SummaryCard(title: 'Monthly Billing', value: _loadingStats ? '...' : _money(_monthlyBilling), icon: Icons.receipt_long_outlined),
                _SummaryCard(title: 'Pending Amount', value: _loadingStats ? '...' : _money(_pendingAmount), icon: Icons.account_balance_wallet_outlined),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Quick actions', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _QuickAction(icon: Icons.local_drink_outlined, title: 'Daily milk entry', subtitle: 'Record today’s delivery', onTap: () => _open(context, const DailyMilkEntryScreen())),
            _QuickAction(icon: Icons.person_add_alt_1_outlined, title: 'Customers', subtitle: 'View and manage customers', onTap: () => _open(context, const CustomerListScreen())),
            _QuickAction(icon: Icons.payments_outlined, title: 'Record a payment', subtitle: 'Add a customer payment', onTap: () => _open(context, const PaymentCollectionScreen())),
            _QuickAction(icon: Icons.receipt_long_outlined, title: 'Monthly bills', subtitle: 'Review and share bills', onTap: () => _open(context, const MonthlyBillingScreen())),
          ],
        ),
      ),
    );
  }

  String _money(double amount) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(amount);

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _loadStats();
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 44) / 2,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE1EFF6))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: const Color(0xFFE1F5FE), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppTheme.primaryColor, size: 22)),
              const SizedBox(height: 14),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE1EFF6))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFE1F5FE), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppTheme.primaryColor)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
