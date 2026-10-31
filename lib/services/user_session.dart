
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserSession {
  UserSession._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get uid => FirebaseAuth.instance.currentUser?.uid;

  static Map<String, dynamic>? _profile;

  static Map<String, dynamic>? get profile => _profile;

  static String get role => _profile?['role'] as String? ?? '';

  static bool get isActive => _profile?['isActive'] == true;

  static String get name => _profile?['name'] as String? ?? '';

  static Map<String, dynamic> get permissions {
    final raw = _profile?['permissions'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  static Future<bool> load() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _profile = null;
      return false;
    }

    final doc = await _db
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (!doc.exists) {
      _profile = null;
      return false;
    }

    final data = doc.data();

    if (data == null || data['isActive'] != true) {
      _profile = null;
      return false;
    }

    _profile = data;
    return true;
  }

  static bool can(String module, String action) {
    final modulePermissions = permissions[module];

    if (modulePermissions is! Map) return false;

    return modulePermissions[action] == true;
  }

  static void clear() {
    _profile = null;
  }

  static CollectionReference<Map<String, dynamic>> collection(
      String name,
      ) {
    final currentUid = uid;

    if (currentUid == null || !isActive) {
      throw StateError('No active user session.');
    }

    return _db
        .collection('users')
        .doc(currentUid)
        .collection(name);
  }
}
