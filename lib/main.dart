import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen/auth_screen.dart';
import 'screen/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  bool rememberMe = prefs.getBool('remember_me') ?? false;
  
  User? user = FirebaseAuth.instance.currentUser;

  if (!rememberMe && user != null) {
    await FirebaseAuth.instance.signOut();
    user = null;
  }

  // Pass the initial user state to the App class
  runApp(CampusSyncApp(initialUser: user, rememberMe: rememberMe));
}

class CampusSyncApp extends StatelessWidget {
  final User? initialUser;
  final bool rememberMe;

  const CampusSyncApp({super.key, this.initialUser, required this.rememberMe});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Poppins',
        primaryColor: Colors.white,
      ),
      // Logic: User must exist, be verified, AND have checked rememberMe
      home: (initialUser != null && initialUser!.emailVerified && rememberMe) 
          ? const DashboardScreen() 
          : const AuthScreen(),
    );
  }
}