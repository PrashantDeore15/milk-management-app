
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/customer_models.dart';
import '../database/database_helper.dart';


class AddCustomerScreen extends StatefulWidget {
  final CustomerModel? customer;

  const AddCustomerScreen({
    super.key,
    this.customer,
  });

  @override
  State<AddCustomerScreen> createState() =>
      _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _rate = TextEditingController();
  final _quantity = TextEditingController();

  String _milkType = 'cow';
  Map<String, double> _milkRates = const {'cow': 60, 'standard': 65, 'full_cream': 70};
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  bool get isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();

    final c = widget.customer;
    if (c != null) {
      _name.text = c.name;
      _mobile.text = c.mobile;
      _address.text = c.address;
      _rate.text = c.rate.toString();
      _quantity.text = c.morningQuantity.toString();
      _milkType = c.milkType;
      if (_milkType == 'buffalo') _milkType = 'standard';

      _startDate =
          DateTime.tryParse(c.startDate) ?? DateTime.now();
    } else {
      _quantity.text = '1';
    }
    _loadMilkRates();
  }

  Future<void> _loadMilkRates() async {
    final rates = await DatabaseHelper.instance.getMilkRates();
    if (!mounted) return;
    setState(() {
      _milkRates = rates;
      _rate.text = (_milkRates[_milkType] ?? 60).toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    _rate.dispose();
    _quantity.dispose();
    super.dispose();
  }

  String? _requiredText(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field आवश्यक आहे';
    }
    return null;
  }

  String? _validateNumber(
      String? value, {
        required String field,
        required bool allowZero,
      }) {
    final number = double.tryParse(value?.trim() ?? '');

    if (number == null || !number.isFinite) {
      return '$field योग्य प्रकारे भरा';
    }

    if (allowZero ? number < 0 : number <= 0) {
      return allowZero
          ? '$field ऋण असू शकत नाही'
          : '$field शून्यापेक्षा जास्त असावा';
    }

    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final oldCustomer = widget.customer;
      final now = DateTime.now();

      final customer = CustomerModel(
        id: oldCustomer?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        mobile: _mobile.text.trim(),
        address: _address.text.trim(),
        milkType: _milkType,
        rate: _milkRates[_milkType] ?? double.parse(_rate.text.trim()),
        morningQuantity: double.parse(_quantity.text.trim()),
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        isActive: oldCustomer?.isActive ?? true,
        createdAt: oldCustomer?.createdAt ??
            now.toIso8601String(),
      );

      if (oldCustomer == null) {
        await DatabaseHelper.instance.addCustomer(
          customer.toMap(),
        );
      } else {
        await DatabaseHelper.instance.updateCustomer(
          customer.id,
          customer.toMap(),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'ग्राहकाची माहिती अपडेट झाली'
                : 'नवीन ग्राहक सेव्ह झाला',
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('सेव्ह करताना त्रुटी: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Customer' : 'Add Customer',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Customer Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => _requiredText(v, 'नाव'),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Mobile Number *',
                prefixIcon: Icon(Icons.phone_android),
                counterText: '',
              ),
              validator: (v) {
                if (v == null ||
                    !RegExp(r'^[6-9][0-9]{9}$')
                        .hasMatch(v.trim())) {
                  return 'योग्य 10 अंकी भारतीय मोबाईल नंबर भरा';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Full Address',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (v) => _requiredText(v, 'पत्ता'),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _milkType,
              decoration: const InputDecoration(
                labelText: 'Milk Type',
                prefixIcon: Icon(Icons.water_drop_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'cow',
                  child: Text('Cow Milk'),
                ),
                DropdownMenuItem(
                  value: 'standard',
                  child: Text('Standard Milk'),
                ),
                DropdownMenuItem(
                  value: 'full_cream',
                  child: Text('Full Cream Milk'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _milkType = value;
                    _rate.text = (_milkRates[value] ?? 0).toStringAsFixed(2);
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _rate,
              readOnly: true,
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Rate per Liter (₹) *',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
              validator: (v) => _validateNumber(
                v,
                field: 'दर',
                allowZero: false,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _quantity,
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Morning Milk Quantity (Liters) *',
                prefixIcon: Icon(Icons.local_drink_outlined),
              ),
              validator: (v) => _validateNumber(
                v,
                field: 'दूधाचे प्रमाण',
                allowZero: true,
              ),
            ),
            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Delivery Start: '
                    '${DateFormat('dd-MM-yyyy').format(_startDate)}',
              ),
            ),
            const SizedBox(height: 28),

            ElevatedButton.icon(
              onPressed: _saving ? null : _saveCustomer,
              icon: _saving
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _saving
                    ? 'Saving...'
                    : isEditing
                    ? 'Update Customer'
                    : 'Save Customer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
