import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen/auth_screen.dart';
import 'screen/dashboard_screen.dart';

void main() async {
  // 1. Initialize Flutter and Firebase
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const CampusSyncApp());
}

class CampusSyncApp extends StatelessWidget {
  const CampusSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CampusSync',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: const Color(
          0xFF121212,
        ), // Deep dark background
        primaryColor: Colors.white,
      ),
      // The app always starts with the Splash Screen
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // 2. Add a artificial delay so the user actually sees your splash screen
    // Adjust the duration (e.g., 2 or 3 seconds) as per your branding needs
    await Future.delayed(const Duration(seconds: 3));

    final prefs = await SharedPreferences.getInstance();
    final bool rememberMe = prefs.getBool('remember_me') ?? false;
    User? user = FirebaseAuth.instance.currentUser;

    // 3. Logic: If "Remember Me" is off, force a sign-out if a user session exists
    if (!rememberMe && user != null) {
      await FirebaseAuth.instance.signOut();
      user = null;
    }

    // 4. Determine final destination
    // User must exist, be verified (if required), and have chosen 'Remember Me'
    bool canAutoLogin = (user != null && user.emailVerified && rememberMe);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              canAutoLogin ? const DashboardScreen() : const AuthScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Replace this Icon with your actual logo Image.asset()
            Icon(Icons.sync_rounded, size: 100, color: Colors.blueAccent),
            SizedBox(height: 24),
            Text(
              'CampusSync',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 40),
            // A subtle loader to show the app is working
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
            ),
          ],
        ),
      ),
    );
  }
}
