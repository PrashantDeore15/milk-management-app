import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

  static const _labels = {
    'cow_milk': 'Cow Milk',
    'buffalo_milk': 'Buffalo Milk',
    'fresh_milk': 'Fresh Milk',
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
      if (!UserSession.can('settings', 'edit')) {
        throw StateError('You do not have permission to edit settings.');
      }
      final rates = {
        for (final key in _labels.keys)
          key: double.parse(_controllers[key]!.text.trim()),
      };

      await UserSession.collection('settings').doc('milk_rates').set({
        'extra_item_rates': rates,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Extra milk item rates saved.')),
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
                        Text('These prices are used for Cow Milk, Buffalo Milk, and Fresh Milk extra items.', style: TextStyle(color: Colors.white)),
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
                      label: Text(_saving ? 'Saving...' : 'Save Milk Item Rates'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
