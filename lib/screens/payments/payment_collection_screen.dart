
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_data_service.dart';
import '../../services/user_session.dart';

class PaymentCollectionScreen extends StatefulWidget {
  const PaymentCollectionScreen({super.key});

  @override
  State<PaymentCollectionScreen> createState() =>
      _PaymentCollectionScreenState();
}

class _PaymentCollectionScreenState
    extends State<PaymentCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _payments = [];

  String? _customerId;
  String _paymentMode = 'cash';
  DateTime _paymentDate = DateTime.now();

  bool _loading = true;
  bool _saving = false;
  bool _loadingMonthlyHistory = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await FirestoreDataService.instance.getCustomers();

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loading = false;

        if (_customerId == null && customers.isNotEmpty) {
          _customerId = customers.first['id'] as String;
        }
      });

      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('ग्राहक लोड करताना त्रुटी: $e');
    }
  }

  Future<void> _loadPayments() async {
    final id = _customerId;
    if (id == null) {
      if (mounted) setState(() => _payments = []);
      return;
    }

    try {
      final payments = await FirestoreDataService.instance.getPayments(id);

      if (!mounted) return;

      setState(() => _payments = payments);
    } catch (e) {
      if (!mounted) return;
      _message('Payment History लोड झाली नाही: $e');
    }
  }

  Future<void> _showMonthlyPaymentHistory() async {
    if (_loadingMonthlyHistory) return;
    setState(() => _loadingMonthlyHistory = true);
    final now = DateTime.now();
    final startDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month));
    final endDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month + 1));

    try {
      final payments = await FirestoreDataService.instance.getAllPaymentsForPeriod(
        startDate: startDate,
        endDate: endDate,
      );
      if (!mounted) return;
      final customerNames = {
        for (final customer in _customers)
          customer['id'].toString(): customer['name']?.toString() ?? 'Customer',
      };
      final monthLabel = DateFormat('MMMM yyyy').format(now);
      final total = payments.fold<double>(
        0,
        (sum, payment) => sum + ((payment['amount'] as num?)?.toDouble() ?? 0),
      );

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Payments received · $monthLabel'),
          content: SizedBox(
            width: 480,
            child: payments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No payments received this month.'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF155A8A)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${payments.length} payments received')),
                            Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.sizeOf(dialogContext).height * .5,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: payments.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final payment = payments[index];
                            final customerId = payment['customer_id']?.toString() ?? '';
                            final mode = (payment['payment_mode'] as String? ?? 'cash').toUpperCase();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFEAF5FC),
                                child: Icon(Icons.payments_outlined, color: Color(0xFF155A8A)),
                              ),
                              title: Text(customerNames[customerId] ?? 'Customer'),
                              subtitle: Text('${payment['payment_date'] ?? ''} · $mode'),
                              trailing: Text(
                                _money(payment['amount']),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (mounted) _message('Could not load this month’s payment history: $error');
    } finally {
      if (mounted) setState(() => _loadingMonthlyHistory = false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected != null && mounted) {
      setState(() => _paymentDate = selected);
    }
  }

  Future<void> _savePayment() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    final customerId = _customerId;
    if (customerId == null) {
      _message('प्रथम ग्राहक तयार करा.');
      return;
    }

    if (!UserSession.can('payments', 'create')) {
      _message('तुम्हाला Payment नोंदवण्याची परवानगी नाही.');
      return;
    }

    final amount = double.parse(_amountController.text.trim());

    setState(() => _saving = true);

    try {
      await FirestoreDataService.instance.addPayment({
        'id': const Uuid().v4(),
        'customer_id': customerId,
        'payment_date':
        DateFormat('yyyy-MM-dd').format(_paymentDate),
        'amount': amount,
        'payment_mode': _paymentMode,
        'reference': _referenceController.text.trim(),
        'notes': _notesController.text.trim(),
        'synced': false,
      });

      _amountController.clear();
      _referenceController.clear();
      _notesController.clear();

      await _loadPayments();

      if (!mounted) return;

      _message('Payment यशस्वीरीत्या सेव्ह झाले.');
    } catch (e) {
      if (!mounted) return;
      _message('Payment सेव्ह करताना त्रुटी: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double get _totalPayments {
    return _payments.fold<double>(
      0,
          (sum, payment) =>
      sum + (payment['amount'] as num).toDouble(),
    );
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toDouble() ?? 0;

    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
          ? const Center(
        child: Text(
          'Payment घेण्यापूर्वी ग्राहक जोडा.',
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loadingMonthlyHistory ? null : _showMonthlyPaymentHistory,
              icon: _loadingMonthlyHistory
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.history),
              label: Text(_loadingMonthlyHistory ? 'Loading payment history...' : 'Payment History · This Month'),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _customerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Customer',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: _customers.map((customer) {
              return DropdownMenuItem<String>(
                value: customer['id'] as String,
                child: Text(
                  '${customer['name']} - ${customer['mobile']}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) async {
              setState(() => _customerId = value);
              await _loadPayments();
            },
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 32,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Total Recorded Payments',
                    ),
                  ),
                  Text(
                    _money(_totalPayments),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Record New Payment',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                  const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Payment Amount (₹)',
                    prefixIcon:
                    Icon(Icons.currency_rupee),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      value?.trim() ?? '',
                    );

                    if (amount == null ||
                        !amount.isFinite ||
                        amount <= 0) {
                      return 'योग्य रक्कम भरा';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _paymentMode,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'cash',
                      child: Text('Cash'),
                    ),
                    DropdownMenuItem(
                      value: 'upi',
                      child: Text('UPI'),
                    ),
                    DropdownMenuItem(
                      value: 'bank',
                      child: Text('Bank Transfer'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentMode = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    'Date: ${DateFormat('dd-MM-yyyy').format(_paymentDate)}',
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Reference (Optional)',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                    _saving ? null : _savePayment,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : 'Save Payment',
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const Text(
            'Payment History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (_payments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'या ग्राहकासाठी Payment History उपलब्ध नाही.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._payments.map((payment) {
              final mode =
                  payment['payment_mode'] as String? ?? 'cash';

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      mode == 'cash'
                          ? Icons.payments_outlined
                          : mode == 'upi'
                          ? Icons.qr_code
                          : Icons.account_balance,
                    ),
                  ),
                  title: Text(
                    _money(payment['amount']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${payment['payment_date']} • ${mode.toUpperCase()}'
                        '${(payment['reference'] as String? ?? '').isEmpty ? '' : '\nRef: ${payment['reference']}'}',
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
