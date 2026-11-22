import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_data_service.dart';
import '../../services/user_session.dart';

class MilkRatesScreen extends StatefulWidget {
  const MilkRatesScreen({super.key});

  @override
  State<MilkRatesScreen> createState() => _MilkRatesScreenState();
}

class _MilkRatesScreenState extends State<MilkRatesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{
    'cow_milk': TextEditingController(),
    'buffalo_milk': TextEditingController(),
    'fresh_milk': TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;
  DateTime _effectiveDate = DateTime.now();

  static const _labels = {
    'cow_milk': 'Cow Milk',
    'buffalo_milk': 'Buffalo Milk',
    'fresh_milk': 'Fresh Cream Milk',
  };

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRates() async {
    try {
      if (UserSession.uid == null || !UserSession.isActive) {
        throw StateError('No active user session.');
      }

      final rates = await FirestoreDataService.instance.getMilkRates();

      for (final key in _labels.keys) {
        _controllers[key]!.text = rates[key]!.toStringAsFixed(2);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load rates: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRates() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final rates = {
        for (final key in _labels.keys)
          key: double.parse(_controllers[key]!.text.trim()),
      };

      await FirestoreDataService.instance.saveDatedMilkRates(
        effectiveDate: DateFormat('yyyy-MM-dd').format(_effectiveDate),
        rates: rates,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Milk rates saved for this date and later.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save rates: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Milk Rates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)]),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.water_drop_rounded, color: Colors.white, size: 34),
                        SizedBox(height: 12),
                        Text('Set extra milk item prices', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 5),
                        Text('These prices are used for Cow Milk, Buffalo Milk, and Fresh Cream Milk extra items.', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rates effective from'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(_effectiveDate)),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _effectiveDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) {
                        setState(() => _effectiveDate = picked);
                      }
                    },
                  ),
                  for (final entry in _labels.entries) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFDCEEF7))),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextFormField(
                          controller: _controllers[entry.key],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: entry.value,
                            prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppTheme.primaryColor),
                            suffixText: 'per liter',
                          ),
                          validator: (value) {
                            final rate = double.tryParse(value?.trim() ?? '');
                            if (rate == null || !rate.isFinite || rate <= 0) return 'Enter a rate greater than zero';
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveRates,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Saving...' : 'Save Milk Item Rates'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
