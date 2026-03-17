import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/app_colors.dart'; 
import 'auth_screen.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'), 
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png', // Hexagonal logo
                width: 150,
              errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.broken_image, size: 100, color: Colors.red);
        },
              )
              .animate()
              .fade(duration: 1000.ms)
              .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.1, 1.1), duration: 1500.ms, curve: Curves.easeOutBack)
              .then()
              .shimmer(duration: 1500.ms, color: AppColors.wisteria),
              const SizedBox(height: 20),
              Text(
                'Campus Sync',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.brightGray,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ).animate().fade(delay: 1000.ms).slideY(begin: 1, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}