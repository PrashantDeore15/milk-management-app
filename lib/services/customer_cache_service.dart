import '../models/customer_models.dart';
import '../screens/database/database_helper.dart';
import 'firestore_data_service.dart';

class CustomerCacheService {
  CustomerCacheService._();

  static Future<void> refresh() async {
    try {
      final customers =
          await FirestoreDataService.instance.getCustomers(activeOnly: false);
      await DatabaseHelper.instance.syncCustomers(
        customers
            .map((customer) => CustomerModel.fromFirestore(
                  customer['id']?.toString() ?? '',
                  customer,
                ).toMap())
            .toList(),
      );
    } catch (_) {
      // Keep the existing local cache available when Firestore is offline.
    }
  }
}
