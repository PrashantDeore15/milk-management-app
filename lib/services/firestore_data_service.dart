
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_session.dart';

class FirestoreDataService {
  FirestoreDataService._();

  static final FirestoreDataService instance =
  FirestoreDataService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --------------------------------------------------
  // COMMON COLLECTION AND PERMISSION HANDLER
  // --------------------------------------------------

  CollectionReference<Map<String, dynamic>> _collection(
      String collectionName,
      String permission, {
        String? permissionModule,
      }) {
    final module = permissionModule ?? collectionName;

    if (!UserSession.can(module, permission)) {
      throw StateError(
        'You do not have permission to $permission $module.',
      );
    }

    return UserSession.collection(collectionName);
  }

  // --------------------------------------------------
  // CUSTOMERS
  // --------------------------------------------------

  Future<void> addCustomer(
      Map<String, dynamic> customer,
      ) async {
    final ref = _collection('customers', 'create').doc();

    await ref.set({
      ...customer,
      'id': ref.id,
      'createdBy': UserSession.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getCustomers({
    bool activeOnly = true,
  }) async {
    final ref = _collection('customers', 'view');

    final snapshot = await ref.get();

    final customers = snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();

    final filtered = activeOnly
        ? customers.where((customer) {
      return customer['is_active'] != false &&
          customer['is_active'] != 0;
    }).toList()
        : customers;

    filtered.sort((a, b) {
      final nameA =
      (a['name'] ?? '').toString().toLowerCase();

      final nameB =
      (b['name'] ?? '').toString().toLowerCase();

      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  Future<void> updateCustomer(
      String id,
      Map<String, dynamic> values,
      ) async {
    final ref = _collection('customers', 'edit');

    await ref.doc(id).update({
      ...values,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deactivateCustomer(String id) async {
    final ref = _collection('customers', 'edit');

    await ref.doc(id).update({
      'is_active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCustomer(String id) async {
    final ref = _collection('customers', 'delete');

    await ref.doc(id).delete();
  }

  // --------------------------------------------------
  // DAILY MILK ENTRIES
  // Firestore collection: milk_entries
  // Permission module: milkEntries
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getMilkEntries(
      String date,
      ) async {
    final ref = _collection(
      'milk_entries',
      'view',
      permissionModule: 'milkEntries',
    );

    final snapshot = await ref
        .where('entry_date', isEqualTo: date)
        .get();

    return snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();
  }

  Future<void> saveMilkEntry(
      Map<String, dynamic> entry,
      ) async {
    final customerId =
    entry['customer_id']?.toString();

    final date =
    entry['entry_date']?.toString();

    if (customerId == null ||
        customerId.isEmpty ||
        date == null ||
        date.isEmpty) {
      throw ArgumentError(
        'customer_id and entry_date are required.',
      );
    }

    // Reading the existing document requires view permission.
    if (!UserSession.can('milkEntries', 'view')) {
      throw StateError(
        'You do not have permission to view milk entries.',
      );
    }

    final id = '${customerId}_$date';

    final ref = UserSession.collection('milk_entries');
    final doc = ref.doc(id);

    final existing = await doc.get();

    final permission =
    existing.exists ? 'edit' : 'create';

    if (!UserSession.can('milkEntries', permission)) {
      throw StateError(
        'You do not have permission to $permission milk entries.',
      );
    }

    await doc.set({
      ...entry,
      'id': id,
      'customer_id': customerId,
      'entry_date': date,
      'delivered': entry['delivered'] == true ||
          entry['delivered'] == 1,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': UserSession.uid,
    }, SetOptions(merge: true));
  }

  // --------------------------------------------------
  // CUSTOMER DAILY PRODUCTS
  // Firestore collection: customer_daily_products
  // Permission module: customerDailyProducts
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getCustomerDailyProducts(
      String customerId,
      String date,
      ) async {
    final ref = _collection(
      'customer_daily_products',
      'view',
      permissionModule: 'customerDailyProducts',
    );

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('entry_date', isEqualTo: date)
        .get();

    return snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();
  }

  Future<void> saveCustomerDailyProducts(
      List<Map<String, dynamic>> products,
      String customerId,
      String date,
      ) async {
    final ref = _collection(
      'customer_daily_products',
      'create',
      permissionModule: 'customerDailyProducts',
    );

    if (!UserSession.can(
      'customerDailyProducts',
      'delete',
    )) {
      throw StateError(
        'You need delete permission to replace daily products.',
      );
    }

    final existing = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('entry_date', isEqualTo: date)
        .get();

    // Firestore batch supports a maximum of 500 writes.
    if (existing.docs.length + products.length > 500) {
      throw StateError(
        'Too many daily product records for one batch.',
      );
    }

    final batch = _db.batch();

    // Delete old products for this customer and date.
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }

    // Add the updated products.
    for (final product in products) {
      final productName =
      product['product_name']?.toString();

      if (productName == null || productName.isEmpty) {
        throw ArgumentError(
          'product_name is required.',
        );
      }

      final doc = ref.doc(
        '${customerId}_${date}_$productName',
      );

      batch.set(doc, {
        ...product,
        'id': doc.id,
        'customer_id': customerId,
        'entry_date': date,
        'createdBy': UserSession.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // --------------------------------------------------
  // MILK RATES
  // --------------------------------------------------

  Future<Map<String, double>> getMilkRates() async {
    final ref = _collection('settings', 'view');

    final doc = await ref.doc('milk_rates').get();

    const defaults = <String, double>{
      'cow_milk': 60,
      'buffalo_milk': 65,
      'fresh_milk': 70,
    };

    final result = Map<String, double>.from(defaults);

    final data = doc.data();
    final raw = data?['extra_item_rates'];

    if (raw is Map) {
      for (final key in defaults.keys) {
        final value = raw[key];

        if (value is num && value > 0) {
          result[key] = value.toDouble();
        }
      }
    }

    return result;
  }

  // --------------------------------------------------
  // PAYMENTS
  // --------------------------------------------------

  Future<void> addPayment(
      Map<String, dynamic> payment,
      ) async {
    final ref = _collection('payments', 'create').doc();

    await ref.set({
      ...payment,
      'id': ref.id,
      'createdBy': UserSession.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getPayments(
      String customerId,
      ) async {
    final ref = _collection('payments', 'view');

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .get();

    final rows = snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();

    rows.sort((a, b) {
      return (b['payment_date'] ?? '')
          .toString()
          .compareTo(
        (a['payment_date'] ?? '').toString(),
      );
    });

    return rows;
  }


  // --------------------------------------------------
  // MONTHLY BILLING - FIRESTORE
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getCustomersForBilling() async {
    final ref = _collection('customers', 'view');
    final snapshot = await ref.get();

    return snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).where((customer) {
      final active = customer['is_active'];
      return active == true || active == 1 || active == null;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getMilkEntriesForPeriod({
    required String customerId,
    required String startDate,
    required String endDate,
  }) async {
    final ref = _collection(
      'milk_entries',
      'view',
      permissionModule: 'milkEntries',
    );

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('entry_date', isGreaterThanOrEqualTo: startDate)
        .where('entry_date', isLessThan: endDate)
        .get();

    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .where((entry) =>
    entry['delivered'] == true ||
        entry['delivered'] == 1)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getDailyProductsForPeriod({
    required String customerId,
    required String startDate,
    required String endDate,
  }) async {
    final ref = _collection(
      'customer_daily_products',
      'view',
      permissionModule: 'customerDailyProducts',
    );

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('entry_date', isGreaterThanOrEqualTo: startDate)
        .where('entry_date', isLessThan: endDate)
        .get();

    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getPaymentsForPeriod({
    required String customerId,
    required String startDate,
    required String endDate,
  }) async {
    final ref = _collection('payments', 'view');

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('payment_date', isGreaterThanOrEqualTo: startDate)
        .where('payment_date', isLessThan: endDate)
        .get();

    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getBillsForMonth(
      String billingMonth,
      ) async {
    final ref = _collection('bills', 'view');

    final snapshot = await ref
        .where('billing_month', isEqualTo: billingMonth)
        .get();

    return snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getPreviousBills(
      String customerId,
      String billingMonth,
      ) async {
    final ref = _collection('bills', 'view');

    final snapshot = await ref
        .where('customer_id', isEqualTo: customerId)
        .where('billing_month', isLessThan: billingMonth)
        .get();

    final rows = snapshot.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();

    rows.sort((a, b) {
      return (b['billing_month'] ?? '')
          .toString()
          .compareTo((a['billing_month'] ?? '').toString());
    });

    return rows;
  }

  Future<void> saveBill(
      Map<String, dynamic> bill,
      ) async {
    final id = bill['id']?.toString();

    if (id == null || id.isEmpty) {
      throw ArgumentError('Bill ID is required.');
    }

    final ref = _collection('bills', 'create');

    await ref.doc(id).set({
      ...bill,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': UserSession.uid,
    }, SetOptions(merge: true));
  }

  Future<void> updateBill(
      String id,
      Map<String, dynamic> values,
      ) async {
    final ref = _collection('bills', 'edit');

    await ref.doc(id).update({
      ...values,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getCustomerById(
      String customerId,
      ) async {
    final ref = _collection('customers', 'view');
    final doc = await ref.doc(customerId).get();

    if (!doc.exists) return null;

    return {
      ...doc.data()!,
      'id': doc.id,
    };
  }

}
