import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ SplashScreen now lives in screen/splash_screen.dart
import 'screen/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Enable Firestore offline persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const CampusSyncApp());
}

class CampusSyncApp extends StatelessWidget {
  const CampusSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CampusSync',

      // ── Light theme matching the app's yellow/white/grey palette ──
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        primaryColor: const Color(0xFFFFD166),
        colorScheme: ColorScheme.light(
          primary: const Color(0xFFFFD166),
          secondary: const Color(0xFFE5A91A),
          surface: Colors.white,
          background: const Color(0xFFF0F2F5),
          onPrimary: const Color(0xFF1A1D20),
          onBackground: const Color(0xFF1A1D20),
          onSurface: const Color(0xFF1A1D20),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1A1D20)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1D20),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: 'Poppins',
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              color: Color(0xFF1A1D20),
              fontWeight: FontWeight.w900,
              fontFamily: 'Poppins'),
          headlineMedium: TextStyle(
              color: Color(0xFF1A1D20),
              fontWeight: FontWeight.w800,
              fontFamily: 'Poppins'),
          bodyMedium: TextStyle(
              color: Color(0xFF6C757D),
              fontFamily: 'Poppins'),
        ),
      ),

      // ✅ Points to the real SplashScreen in screen/splash_screen.dart
      // Auth logic (remember me, email verification) lives there.
      home: const SplashScreen(),
    );
  }
}