
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
    return CustomerModel(
      id: map['id'] as String,
      name: map['name'] as String,
      mobile: map['mobile'] as String,
      address: (map['address'] as String?) ?? '',
      milkType: map['milk_type'] as String,
      rate: (map['rate'] as num).toDouble(),
      morningQuantity:
      (map['morning_quantity'] as num).toDouble(),
      startDate: map['start_date'] as String,
      isActive: (map['is_active'] as int) == 1,
      createdAt: map['created_at'] as String,
    );
  }
}
