
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/user_session.dart';
import '../admin/admin_dashboard.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 2), _openNextScreen);
  }


  Future<void> _openNextScreen() async {
    Widget destination = const LoginScreen();

    try {
      if (FirebaseAuth.instance.currentUser != null) {
        final validProfile = await UserSession.load();
        if (validProfile) {
          destination = const AdminDashboard();
        } else {
          await FirebaseAuth.instance.signOut();
          UserSession.clear();
        }
      }
    } catch (_) {
      // If profile verification fails, return to login safely.
      await FirebaseAuth.instance.signOut();
      UserSession.clear();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF81D4FA),
              Color(0xFF29B6F6),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  size: 76,
                  color: Color(0xFF29B6F6),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'MILK MANAGEMENT',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Smart Milk Delivery & Billing',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF16445A),
                ),
              ),
              const SizedBox(height: 42),
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 70),
              const Text(
                'FRESH MILK • TRUSTED SERVICE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: Color(0xFF16445A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
