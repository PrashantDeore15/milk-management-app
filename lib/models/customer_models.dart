
class CustomerModel {
  final String id;
  final String name;
  final String mobile;
  final String address;
  final String milkType;
  final double rate;
  final double morningQuantity;
  final String startDate;
  final bool isActive;
  final String createdAt;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    required this.milkType,
    required this.rate,
    required this.morningQuantity,
    required this.startDate,
    required this.isActive,
    required this.createdAt,
  });

  // Convert model to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'mobile': mobile,
      'address': address,
      'milk_type': milkType,
      'rate': rate,
      'morning_quantity': morningQuantity,
      'start_date': startDate,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }

  // Keep this method for compatibility with existing SQLite code.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      'address': address,
      'milk_type': milkType,
      'rate': rate,
      'morning_quantity': morningQuantity,
      'start_date': startDate,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory CustomerModel.fromMap(Map<String, Object?> map) {
    final activeValue = map['is_active'];
    final createdValue = map['created_at'];

    return CustomerModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      mobile: map['mobile']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      milkType: map['milk_type']?.toString() ?? 'cow',
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      morningQuantity:
      (map['morning_quantity'] as num?)?.toDouble() ?? 0.0,
      startDate: map['start_date']?.toString() ?? '',
      isActive: activeValue == true ||
          activeValue == 1 ||
          activeValue == '1',
      createdAt: createdValue?.toString() ?? '',
    );
  }

  factory CustomerModel.fromFirestore(
      String documentId,
      Map<String, dynamic> data,
      ) {
    return CustomerModel.fromMap({
      ...data,
      'id': documentId,
    });
  }
}
