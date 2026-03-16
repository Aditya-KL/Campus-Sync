import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // State
  bool _isLogin = true;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _selectedBranch;
  final List<String> _branches = ['CSE', 'ECE', 'ME', 'CE', 'EE', 'IT'];

  // --- FIREBASE LOGIC ---

  Future<void> _submitAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        // Sign In
        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Check Email Verification
        if (!userCredential.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          _showMsg('Please verify your email first!', Colors.orange);
          return;
        }

        // Save Persistence Choice
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', _rememberMe);

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
      } else {
        // Register Logic
        if (_passwordController.text != _confirmPasswordController.text) {
          _showMsg('Passwords do not match!', Colors.red);
          return;
        }

        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await userCredential.user!.sendEmailVerification();
        
        await FirebaseFirestore.instance.collection('students').doc(userCredential.user!.uid).set({
          'name': _nameController.text.trim(),
          'rollNo': _rollController.text.trim(),
          'branch': _selectedBranch,
          'email': _emailController.text.trim(),
        });

        _showMsg('Verification link sent! Check your inbox.', Colors.green);
        await FirebaseAuth.instance.signOut();
        setState(() => _isLogin = true);
      }
    } on FirebaseAuthException catch (e) {
      _showMsg(e.message ?? 'Auth Failed', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendResetLink() async {
    if (_emailController.text.isEmpty) {
      _showMsg('Enter your email first', Colors.orange);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text.trim());
      _showMsg('Reset link sent!', Colors.blue);
      setState(() => _isForgotPassword = false);
    } catch (e) {
      _showMsg('Error sending link', Colors.red);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // --- UI TILES ---

  Widget _buildGlassTile({required Widget child, required Key key}) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _loginTile() {
    return _buildGlassTile(
      key: const ValueKey('login'),
      child: Column(
        children: [
          const Text('Campus Sync', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 25),
          _input(_emailController, 'Email', Icons.email),
          const SizedBox(height: 15),
          _input(_passwordController, 'Password', Icons.lock, isPass: true),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v!),
                activeColor: Colors.white, checkColor: Colors.black,
              ),
              const Text('Remember Me', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isForgotPassword = true),
                child: const Text('Forgot Password?', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _btn('LOGIN', _submitAuth),
          TextButton(onPressed: () => setState(() => _isLogin = false), child: const Text('Create Account', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _signupTile() {
    return _buildGlassTile(
      key: const ValueKey('signup'),
      child: Column(
        children: [
          const Text('Register', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          _input(_nameController, 'Name', Icons.person),
          const SizedBox(height: 10),
          _input(_emailController, 'Email', Icons.email),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _input(_rollController, 'Roll No', Icons.numbers)),
              const SizedBox(width: 10),
              Expanded(child: _branchDrop()),
            ],
          ),
          const SizedBox(height: 10),
          _input(_passwordController, 'Password', Icons.lock, isPass: true),
          const SizedBox(height: 10),
          _input(_confirmPasswordController, 'Confirm', Icons.lock_outline, isPass: true),
          const SizedBox(height: 20),
          _btn('REGISTER', _submitAuth),
          TextButton(onPressed: () => setState(() => _isLogin = true), child: const Text('Back to Login', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _forgotPasswordTile() {
    return _buildGlassTile(
      key: const ValueKey('forgot'),
      child: Column(
        children: [
          const Text('Reset Password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Enter your email to receive a reset link.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          _input(_emailController, 'Email', Icons.email),
          const SizedBox(height: 20),
          _btn('SEND LINK', _sendResetLink),
          TextButton(onPressed: () => setState(() => _isForgotPassword = false), child: const Text('Back to Login', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  // --- HELPERS ---

  Widget _input(TextEditingController controller, String hint, IconData icon, {bool isPass = false}) {
    return TextField(
      controller: controller, obscureText: isPass,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true, fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _branchDrop() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBranch, hint: const Text('Branch', style: TextStyle(color: Colors.white60, fontSize: 13)),
          dropdownColor: Colors.black, icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(color: Colors.white)))).toList(),
          onChanged: (v) => setState(() => _selectedBranch = v),
        ),
      ),
    );
  }

  Widget _btn(String txt, VoidCallback tap) {
    return SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: _isLoading ? null : tap,
        child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text(txt, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/background.jpg'), fit: BoxFit.cover),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _isForgotPassword 
                  ? _forgotPasswordTile() 
                  : (_isLogin ? _loginTile() : _signupTile()),
            ),
          ),
        ),
      ),
    );
  }
}