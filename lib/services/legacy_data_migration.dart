import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/database/database_helper.dart';
import 'user_session.dart';

/// Copies records left in the old on-device database into the signed-in
/// user's Firestore collections. Existing cloud documents are left untouched.
class LegacyDataMigration {
  LegacyDataMigration._();

  static const _completeKeyPrefix = 'legacy_sqlite_to_firestore_v1_';

  static Future<void> run() async {
    if (!UserSession.isActive || UserSession.uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final completeKey = '$_completeKeyPrefix${UserSession.uid}';
    if (prefs.getBool(completeKey) == true) return;

    final db = await DatabaseHelper.instance.database;
    final tables = <(String, String, String, String)>[
      ('customers', 'customers', 'customers', 'id'),
      ('milk_entries', 'milk_entries', 'milkEntries', 'id'),
      ('customer_daily_products', 'customer_daily_products', 'customerDailyProducts', 'id'),
      ('payments', 'payments', 'payments', 'id'),
      ('bills', 'bills', 'bills', 'id'),
      ('delivery_pauses', 'delivery_pauses', 'deliveryPauses', 'id'),
    ];

    for (final (table, collection, module, idColumn) in tables) {
      final records = await db.query(table);
      if (records.isEmpty) continue;
      if (!UserSession.can(module, 'create')) {
        throw StateError('Missing create permission for $module while migrating local records.');
      }
      final target = UserSession.collection(collection);
      WriteBatch? batch;
      var writes = 0;
      Future<void> commit() async {
        if (batch != null && writes > 0) await batch!.commit();
        batch = null;
        writes = 0;
      }

      for (final row in records) {
        final rawId = row[idColumn]?.toString();
        final id = table == 'milk_entries'
            ? '${row['customer_id']}_${row['entry_date']}'
            : table == 'customer_daily_products'
                ? '${row['customer_id']}_${row['entry_date']}_${row['product_name']}'
                : (rawId == null || rawId.isEmpty)
            ? '${row['customer_id']}_${row['entry_date']}_${row['product_name'] ?? row['payment_date'] ?? row['billing_month'] ?? 'record'}'
            : rawId;
        final ref = target.doc(id);
        if ((await ref.get()).exists) continue;
        batch ??= FirebaseFirestore.instance.batch();
        final data = Map<String, dynamic>.from(row)..remove('synced');
        data['id'] = id;
        data['migratedFromSqlite'] = true;
        batch!.set(ref, data);
        writes++;
        if (writes >= 450) await commit();
      }
      await commit();
    }

    final rates = await DatabaseHelper.instance.getMilkRates();
    if (rates.isNotEmpty && UserSession.can('settings', 'edit')) {
      final ref = UserSession.collection('settings').doc('milk_rates');
      if (!(await ref.get()).exists) {
        await ref.set({'extra_item_rates': rates, 'migratedFromSqlite': true});
      }
    }
    await prefs.setBool(completeKey, true);
  }
}
