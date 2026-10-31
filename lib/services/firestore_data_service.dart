
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_session.dart';

class FirestoreDataService {
  FirestoreDataService._();

  static final FirestoreDataService instance =
  FirestoreDataService._();

  CollectionReference<Map<String, dynamic>> _collection(
      String name,
      String permission,
      ) {
    if (!UserSession.can(name, permission)) {
      throw StateError(
        'You do not have permission to $permission $name.',
      );
    }

    return UserSession.collection(name);
  }

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
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  Future<void> updateCustomer(
      String id,
      Map<String, dynamic> values,
      ) async {
    final ref = _collection('customers', 'edit');

    await ref.doc(id).update(values);
  }

  Future<void> deactivateCustomer(String id) async {
    final ref = _collection('customers', 'edit');

    await ref.doc(id).update({
      'is_active': false,
    });
  }

  Future<void> deleteCustomer(String id) async {
    final ref = _collection('customers', 'delete');

    await ref.doc(id).delete();
  }
}
