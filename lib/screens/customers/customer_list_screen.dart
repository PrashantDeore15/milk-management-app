
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

import '../../models/customer_models.dart';
import '../database/database_helper.dart';
import 'add_customer_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState
    extends State<CustomerListScreen> {
  final _searchController = TextEditingController();

  List<CustomerModel> _customers = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    if (mounted) setState(() => _loading = true);

    try {
      final rows =
      await DatabaseHelper.instance.getCustomers();

      final customers = rows
          .map((row) => CustomerModel.fromMap(row))
          .toList();

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ग्राहक लोड झाले नाहीत: $e')),
      );
    }
  }

  List<CustomerModel> get _filteredCustomers {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) return _customers;

    return _customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.mobile.contains(query) ||
          customer.address.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addCustomer() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddCustomerScreen(),
      ),
    );

    if (result == true) _loadCustomers();
  }

  Future<void> _editCustomer(CustomerModel customer) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCustomerScreen(
          customer: customer,
        ),
      ),
    );

    if (result == true) _loadCustomers();
  }

  Future<void> _deactivateCustomer(
      CustomerModel customer,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate Customer?'),
        content: Text(
          '${customer.name} यांचा जुना रेकॉर्ड कायम ठेवून '
              'त्यांना Active यादीतून काढायचे आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DatabaseHelper.instance.deactivateCustomer(
        customer.id,
      );
      await _loadCustomers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ग्राहक Deactivate झाला'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटी: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filteredCustomers;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _query = value);
              },
              decoration: InputDecoration(
                hintText: 'Search name, mobile or address...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: Row(
              children: [
                const Text(
                  'Active Customers',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text('${customers.length}'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
              child: CircularProgressIndicator(),
            )
                : customers.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 60,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _query.isEmpty
                        ? 'No customers yet'
                        : 'No matching customers found',
                  ),
                  if (_query.isEmpty)
                    const SizedBox(height: 12),
                  if (_query.isEmpty)
                    FilledButton.icon(
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add First Customer',
                      ),
                    ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadCustomers,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  12, 4, 12, 90,
                ),
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];

                  return Card(
                    margin: const EdgeInsets.only(
                      bottom: 10,
                    ),
                    child: ListTile(
                      contentPadding:
                      const EdgeInsets.all(12),
                      leading: CircleAvatar(
                        backgroundColor:
                        const Color(0xFFE1F5FE),
                        child: Icon(
                          Icons.person,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      title: Text(
                        customer.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Padding(
                        padding:
                        const EdgeInsets.only(top: 6),
                        child: Text(
                          '${customer.mobile}\n'
                              '${customer.milkType == 'cow' ? 'Cow Milk' : 'Buffalo Milk'}'
                              ' • ${customer.morningQuantity} L/day\n'
                              '₹${customer.rate.toStringAsFixed(2)} / L',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editCustomer(customer);
                          } else if (action == 'deactivate') {
                            _deactivateCustomer(customer);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'deactivate',
                            child: Text('Deactivate'),
                          ),
                        ],
                      ),
                      onTap: () =>
                          _editCustomer(customer),
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
}
