
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/customer_models.dart';
import '../../services/user_session.dart';
import 'add_customer_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
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

  // Load customers from the signed-in user's Firestore collection.
  Future<void> _loadCustomers() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      if (UserSession.uid == null || !UserSession.isActive) {
        throw StateError('No active user session.');
      }

      if (!UserSession.can('customers', 'view')) {
        throw StateError(
          'You do not have permission to view customers.',
        );
      }

      final snapshot =
      await UserSession.collection('customers').get();

      final customers = snapshot.docs.map((doc) {
        final data = doc.data();

        // Adapt Firestore fields to the existing SQLite-style model.
        return CustomerModel.fromFirestore(
          doc.id,
          data,
        );
      }).where((customer) => customer.isActive).toList();

      customers.sort(
            (a, b) => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      );

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ग्राहक लोड झाले नाहीत: $e'),
        ),
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
    if (!UserSession.can('customers', 'create')) {
      _showMessage('तुम्हाला ग्राहक जोडण्याची परवानगी नाही.');
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddCustomerScreen(),
      ),
    );

    if (result == true) {
      await _loadCustomers();
    }
  }

  Future<void> _editCustomer(CustomerModel customer) async {
    if (!UserSession.can('customers', 'edit')) {
      _showMessage('तुम्हाला ग्राहक Edit करण्याची परवानगी नाही.');
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCustomerScreen(
          customer: customer,
        ),
      ),
    );

    if (result == true) {
      await _loadCustomers();
    }
  }

  Future<void> _deactivateCustomer(
      CustomerModel customer,
      ) async {
    if (!UserSession.can('customers', 'edit')) {
      _showMessage(
        'तुम्हाला ग्राहक Deactivate करण्याची परवानगी नाही.',
      );
      return;
    }

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
      // The path is scoped to the authenticated user's UID.
      await UserSession.collection('customers')
          .doc(customer.id.toString())
          .update({
        'is_active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadCustomers();

      if (!mounted) return;

      _showMessage('ग्राहक Deactivate झाला');
    } on FirebaseException catch (e) {
      if (!mounted) return;

      _showMessage(
        'Firestore त्रुटी: ${e.message ?? e.code}',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage('त्रुटी: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                  if (_query.isEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add First Customer',
                      ),
                    ),
                  ],
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
                      onTap: () => _editCustomer(customer),
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
