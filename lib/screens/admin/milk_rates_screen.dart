import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../database/database_helper.dart';

class MilkRatesScreen extends StatefulWidget {
  const MilkRatesScreen({super.key});

  @override
  State<MilkRatesScreen> createState() => _MilkRatesScreenState();
}

class _MilkRatesScreenState extends State<MilkRatesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{
    'cow': TextEditingController(),
    'standard': TextEditingController(),
    'full_cream': TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;

  static const _labels = {
    'cow': 'Cow Milk',
    'standard': 'Standard Milk',
    'full_cream': 'Full Cream Milk',
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
      final rates = await DatabaseHelper.instance.getMilkRates();
      for (final key in _labels.keys) {
        _controllers[key]!.text = (rates[key] ?? 0).toStringAsFixed(2);
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
      final rates = {for (final key in _labels.keys) key: double.parse(_controllers[key]!.text.trim())};
      await DatabaseHelper.instance.saveMilkRates(rates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Milk rates saved and applied to customers.')));
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
                        Text('Set your milk prices', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 5),
                        Text('Saved rates update customers and are used for new daily entries.', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
                      label: Text(_saving ? 'Saving...' : 'Save and Apply Rates'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
